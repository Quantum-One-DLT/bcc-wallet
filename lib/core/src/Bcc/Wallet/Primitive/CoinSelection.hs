{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE RecordWildCards #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

-- |
-- Copyright: © 2021 TBCO
-- License: Apache-2.0
--
-- This module provides a high-level interface for coin selection.
--
-- It handles the following responsibilities:
--
--  - selecting inputs from the UTxO set to pay for user-specified outputs;
--  - selecting inputs from the UTxO set to pay for collateral;
--  - producing change outputs to return excess value to the wallet;
--  - balancing a selection to pay for the transaction fee.
--
-- Use the 'performSelection' function to perform a coin selection.
--
module Bcc.Wallet.Primitive.CoinSelection
    ( performSelection
    , SelectionCollateralRequirement (..)
    , SelectionConstraints (..)
    , SelectionParams (..)
    , SelectionError (..)
    , Selection
    , SelectionOf (..)

    , prepareOutputs
    , ErrPrepareOutputs (..)
    , ErrOutputTokenBundleSizeExceedsLimit (..)
    , ErrOutputTokenQuantityExceedsLimit (..)

    -- * Queries
    , selectionDelta

    -- * Reporting
    , SelectionReport (..)
    , SelectionReportSummarized (..)
    , SelectionReportDetailed (..)
    , makeSelectionReport
    , makeSelectionReportSummarized
    , makeSelectionReportDetailed
    ) where

import Prelude

import Bcc.Wallet.Primitive.CoinSelection.Balance
    ( SelectionLimit, SelectionSkeleton )
import Bcc.Wallet.Primitive.Types.Address
    ( Address )
import Bcc.Wallet.Primitive.Types.Coin
    ( Coin (..) )
import Bcc.Wallet.Primitive.Types.TokenBundle
    ( TokenBundle )
import Bcc.Wallet.Primitive.Types.TokenMap
    ( AssetId, TokenMap )
import Bcc.Wallet.Primitive.Types.TokenQuantity
    ( TokenQuantity )
import Bcc.Wallet.Primitive.Types.Tx
    ( TokenBundleSizeAssessment (..)
    , TokenBundleSizeAssessor (..)
    , TxIn
    , TxOut
    , txOutMaxTokenQuantity
    )
import Bcc.Wallet.Primitive.Types.UTxO
    ( UTxO )
import Bcc.Wallet.Primitive.Types.UTxOSelection
    ( UTxOSelection )
import Control.Monad.Random.Class
    ( MonadRandom )
import Control.Monad.Trans.Except
    ( ExceptT (..), except, withExceptT )
import Data.Generics.Internal.VL.Lens
    ( over, view )
import Data.Generics.Labels
    ()
import Data.List.NonEmpty
    ( NonEmpty (..) )
import Data.Semigroup
    ( mtimesDefault )
import Data.Word
    ( Word16 )
import Fmt
    ( Buildable (..), genericF )
import GHC.Generics
    ( Generic )
import GHC.Stack
    ( HasCallStack )
import Numeric.Natural
    ( Natural )

import qualified Bcc.Wallet.Primitive.CoinSelection.Balance as Balance
import qualified Bcc.Wallet.Primitive.Types.TokenBundle as TokenBundle
import qualified Bcc.Wallet.Primitive.Types.TokenMap as TokenMap
import qualified Data.Foldable as F
import qualified Data.Set as Set

-- | Performs a coin selection.
--
-- This function has the following responsibilities:
--
--  - selecting inputs from the UTxO set to pay for user-specified outputs;
--  - selecting inputs from the UTxO set to pay for collateral;
--  - producing change outputs to return excess value to the wallet;
--  - balancing a selection to pay for the transaction fee.
--
performSelection
    :: (HasCallStack, MonadRandom m)
    => SelectionConstraints
    -> SelectionParams
    -> ExceptT SelectionError m Selection
performSelection constraints params = do
    -- TODO:
    --
    -- https://The-Blockchain-Company.atlassian.net/browse/ADP-1037
    -- Adjust coin selection and fee estimation to handle collateral inputs
    --
    preparedOutputs <- withExceptT SelectionOutputsError $ except
        $ prepareOutputs constraints (view #outputsToCover params)
    withExceptT SelectionBalanceError
        $ fmap mkSelection
        $ ExceptT
        $ uncurry Balance.performSelection
        $ toBalanceConstraintsParams
            ( constraints
            , params {outputsToCover = preparedOutputs}
            )

toBalanceConstraintsParams
    :: (        SelectionConstraints,         SelectionParams)
    -> (Balance.SelectionConstraints, Balance.SelectionParams)
toBalanceConstraintsParams (constraints, params) =
    (balanceConstraints, balanceParams)
  where
    balanceConstraints = Balance.SelectionConstraints
        { computeMinimumBccQuantity =
            view #computeMinimumBccQuantity constraints
        , computeMinimumCost =
            view #computeMinimumCost constraints
        , computeSelectionLimit =
            view #computeSelectionLimit constraints
        , assessTokenBundleSize =
            view (#assessTokenBundleSize . #assessTokenBundleSize) constraints
        }
    balanceParams = Balance.SelectionParams
        { assetsToBurn =
            view #assetsToBurn params
        , assetsToMint =
            view #assetsToMint params
        , extraCoinSource =
            view #rewardWithdrawal params <>
            mtimesDefault
                (view #certificateDepositsReturned params)
                (view #depositAmount constraints)
        , extraCoinSink =
            mtimesDefault
                (view #certificateDepositsTaken params)
                (view #depositAmount constraints)
        , outputsToCover =
            view #outputsToCover params
        , utxoAvailable =
            view #utxoAvailableForInputs params
        }

-- | Makes a selection from an ordinary selection and a collateral selection.
--
-- TODO: [ADP-1037]
-- Adjust this function to accept the result of a collateral selection as a
-- parameter.
--
mkSelection :: Balance.SelectionResult -> Selection
mkSelection balanceResult = Selection
    { inputs = view #inputsSelected balanceResult
    , collateral = [] --TODO: [ADP-1037]
    , outputs = view #outputsCovered balanceResult
    , change = view #changeGenerated balanceResult
    , assetsToMint = view #assetsToMint balanceResult
    , assetsToBurn = view #assetsToBurn balanceResult
    , extraCoinSource = view #extraCoinSource balanceResult
    , extraCoinSink = view #extraCoinSink balanceResult
    }

toBalanceSelection :: Selection -> Balance.SelectionResult
toBalanceSelection selection = Balance.SelectionResult
    { inputsSelected = view #inputs selection
    , outputsCovered = view #outputs selection
    , changeGenerated = view #change selection
    , assetsToMint = view #assetsToMint selection
    , assetsToBurn = view #assetsToBurn selection
    , extraCoinSource = view #extraCoinSource selection
    , extraCoinSink = view #extraCoinSink selection
    }

-- | Computes the delta of the given selection, assuming there is a surplus.
--
selectionDelta
    :: (change -> Coin)
    -- ^ A function to extract the coin value from a change value.
    -> SelectionOf change
    -> Coin
selectionDelta getChangeCoin
    = Balance.selectionSurplusCoin
    . toBalanceSelection
    . over #change (fmap (TokenBundle.fromCoin . getChangeCoin))

-- | Specifies all constraints required for coin selection.
--
-- Selection constraints:
--
--    - place limits on the coin selection algorithm, enabling it to produce
--      selections that are acceptable to the ledger.
--
--    - are dependent on the current set of protocol parameters.
--
--    - are not specific to a given selection.
--
data SelectionConstraints = SelectionConstraints
    { assessTokenBundleSize
        :: TokenBundleSizeAssessor
        -- ^ Assesses the size of a token bundle relative to the upper limit of
        -- what can be included in a transaction output. See documentation for
        -- the 'TokenBundleSizeAssessor' type to learn about the expected
        -- properties of this field.
    , computeMinimumBccQuantity
        :: TokenMap -> Coin
        -- ^ Computes the minimum bcc quantity required for a given output.
    , computeMinimumCost
        :: SelectionSkeleton -> Coin
        -- ^ Computes the minimum cost of a given selection skeleton.
    , computeSelectionLimit
        :: [TxOut] -> SelectionLimit
        -- ^ Computes an upper bound for the number of ordinary inputs to
        -- select, given a current set of outputs.
    , depositAmount
        :: Coin
        -- ^ Amount that should be taken from/returned back to the wallet for
        -- each stake key registration/de-registration in the transaction.
    , maximumCollateralInputCount
        :: Word16
        -- ^ Specifies an inclusive upper bound on the number of unique inputs
        -- that can be selected as collateral.
    , utxoSuitableForCollateral
        :: (TxIn, TxOut) -> Maybe Coin
        -- ^ Indicates whether an individual UTxO entry is suitable for use as
        -- a collateral input. This function should return a 'Coin' value if
        -- (and only if) the given UTxO is suitable for use as collateral.
    }
    deriving Generic

-- | Specifies all parameters that are specific to a given selection.
--
data SelectionParams = SelectionParams
    { assetsToBurn
        :: !TokenMap
        -- ^ Specifies a set of assets to burn.
    , assetsToMint
        :: !TokenMap
        -- ^ Specifies a set of assets to mint.
    , outputsToCover
        :: ![TxOut]
        -- ^ Specifies a set of outputs that must be paid for.
    , rewardWithdrawal
        :: !Coin
        -- ^ Specifies the value of a withdrawal from a reward account.
    , certificateDepositsTaken
        :: !Natural
        -- ^ Number of deposits for stake key registrations.
    , certificateDepositsReturned
        :: !Natural
        -- ^ Number of deposits from stake key de-registrations.
    , collateralRequirement
        :: !SelectionCollateralRequirement
        -- ^ Specifies the collateral requirement for this selection.
    , utxoAvailableForCollateral
        :: !UTxO
        -- ^ Specifies a set of UTxOs that are available for selection as
        -- collateral inputs.
        --
        -- This set is allowed to intersect with 'utxoAvailableForInputs',
        -- since the ledger does not require that these sets are disjoint.
    , utxoAvailableForInputs
        :: !UTxOSelection
        -- ^ Specifies a set of UTxOs that are available for selection as
        -- ordinary inputs and optionally, a subset that has already been
        -- selected.
        --
        -- Further entries from this set will be selected to cover any deficit.
    }
    deriving (Eq, Generic, Show)

-- | Indicates the collateral requirement for a selection.
--
data SelectionCollateralRequirement
    = SelectionCollateralRequired
    -- ^ Indicates that collateral is required.
    | SelectionCollateralNotRequired
    -- ^ Indicates that collateral is not required.
    deriving (Eq, Show)

-- | Indicates that an error occurred while performing a coin selection.
--
data SelectionError
    = SelectionBalanceError Balance.SelectionError
    | SelectionOutputsError ErrPrepareOutputs
    deriving (Eq, Show)

-- | Represents a balanced selection.
--
data SelectionOf change = Selection
    { inputs
        :: !(NonEmpty (TxIn, TxOut))
        -- ^ Selected inputs.
    , collateral
        :: ![(TxIn, TxOut)]
        -- ^ Selected collateral inputs.
    , outputs
        :: ![TxOut]
        -- ^ User-specified outputs
    , change
        :: ![change]
        -- ^ Generated change outputs.
    , assetsToMint
        :: !TokenMap
        -- ^ Assets to mint.
    , assetsToBurn
        :: !TokenMap
        -- ^ Assets to burn.
    , extraCoinSource
        :: !Coin
        -- ^ An extra source of bcc.
    , extraCoinSink
        :: !Coin
        -- ^ An extra sink for bcc.
    }
    deriving (Generic, Eq, Show)

-- | The default type of selection.
--
-- In this type of selection, change values do not have addresses assigned.
--
type Selection = SelectionOf TokenBundle

-- | Prepares the given user-specified outputs, ensuring that they are valid.
--
prepareOutputs
    :: SelectionConstraints
    -> [TxOut]
    -> Either ErrPrepareOutputs [TxOut]
prepareOutputs constraints outputsUnprepared
    | (address, assetCount) : _ <- excessivelyLargeBundles =
        Left $
            -- We encountered one or more excessively large token bundles.
            -- Just report the first such bundle:
            ErrPrepareOutputsTokenBundleSizeExceedsLimit $
            ErrOutputTokenBundleSizeExceedsLimit {address, assetCount}
    | (address, asset, quantity) : _ <- excessiveTokenQuantities =
        Left $
            -- We encountered one or more excessive token quantities.
            -- Just report the first such quantity:
            ErrPrepareOutputsTokenQuantityExceedsLimit $
            ErrOutputTokenQuantityExceedsLimit
                { address
                , asset
                , quantity
                , quantityMaxBound = txOutMaxTokenQuantity
                }
    | otherwise =
        pure outputsToCover
  where
    SelectionConstraints
        { assessTokenBundleSize
        , computeMinimumBccQuantity
        } = constraints

    -- The complete list of token bundles whose serialized lengths are greater
    -- than the limit of what is allowed in a transaction output:
    excessivelyLargeBundles :: [(Address, Int)]
    excessivelyLargeBundles =
        [ (address, assetCount)
        | output <- F.toList outputsToCover
        , let bundle = view #tokens output
        , bundleIsExcessivelyLarge bundle
        , let address = view #address output
        , let assetCount = Set.size $ TokenBundle.getAssets bundle
        ]

      where
        bundleIsExcessivelyLarge b = case assessSize b of
            TokenBundleSizeWithinLimit -> False
            OutputTokenBundleSizeExceedsLimit -> True
          where
            assessSize = view #assessTokenBundleSize assessTokenBundleSize

    -- The complete list of token quantities that exceed the maximum quantity
    -- allowed in a transaction output:
    excessiveTokenQuantities :: [(Address, AssetId, TokenQuantity)]
    excessiveTokenQuantities =
        [ (address, asset, quantity)
        | output <- F.toList outputsToCover
        , let address = view #address output
        , (asset, quantity) <-
            TokenMap.toFlatList $ view #tokens $ view #tokens output
        , quantity > txOutMaxTokenQuantity
        ]

    outputsToCover =
        Balance.prepareOutputsWith computeMinimumBccQuantity outputsUnprepared

-- | Indicates a problem when preparing outputs for a coin selection.
--
data ErrPrepareOutputs
    = ErrPrepareOutputsTokenBundleSizeExceedsLimit
        ErrOutputTokenBundleSizeExceedsLimit
    | ErrPrepareOutputsTokenQuantityExceedsLimit
        ErrOutputTokenQuantityExceedsLimit
    deriving (Eq, Generic, Show)

data ErrOutputTokenBundleSizeExceedsLimit = ErrOutputTokenBundleSizeExceedsLimit
    { address :: !Address
      -- ^ The address to which this token bundle was to be sent.
    , assetCount :: !Int
      -- ^ The number of assets within the token bundle.
    }
    deriving (Eq, Generic, Show)

-- | Indicates that a token quantity exceeds the maximum quantity that can
--   appear in a transaction output's token bundle.
--
data ErrOutputTokenQuantityExceedsLimit = ErrOutputTokenQuantityExceedsLimit
    { address :: !Address
      -- ^ The address to which this token quantity was to be sent.
    , asset :: !AssetId
      -- ^ The asset identifier to which this token quantity corresponds.
    , quantity :: !TokenQuantity
      -- ^ The token quantity that exceeded the bound.
    , quantityMaxBound :: !TokenQuantity
      -- ^ The maximum allowable token quantity.
    }
    deriving (Eq, Generic, Show)

--------------------------------------------------------------------------------
-- Reporting
--------------------------------------------------------------------------------

-- | Includes both summarized and detailed information about a selection.
--
data SelectionReport = SelectionReport
    { summary :: SelectionReportSummarized
    , detail :: SelectionReportDetailed
    }
    deriving (Eq, Generic, Show)

-- | Includes summarized information about a selection.
--
-- Each data point can be serialized as a single line of text.
--
data SelectionReportSummarized = SelectionReportSummarized
    { computedFee :: Coin
    , bccBalanceOfSelectedInputs :: Coin
    , bccBalanceOfExtraCoinSource :: Coin
    , bccBalanceOfExtraCoinSink :: Coin
    , bccBalanceOfRequestedOutputs :: Coin
    , bccBalanceOfGeneratedChangeOutputs :: Coin
    , numberOfSelectedInputs :: Int
    , numberOfSelectedCollateralInputs :: Int
    , numberOfRequestedOutputs :: Int
    , numberOfGeneratedChangeOutputs :: Int
    , numberOfUniqueNonBccAssetsInSelectedInputs :: Int
    , numberOfUniqueNonBccAssetsInRequestedOutputs :: Int
    , numberOfUniqueNonBccAssetsInGeneratedChangeOutputs :: Int
    }
    deriving (Eq, Generic, Show)

-- | Includes detailed information about a selection.
--
data SelectionReportDetailed = SelectionReportDetailed
    { selectedInputs :: [(TxIn, TxOut)]
    , selectedCollateral :: [(TxIn, TxOut)]
    , requestedOutputs :: [TxOut]
    , generatedChangeOutputs :: [TokenBundle.Flat TokenBundle]
    }
    deriving (Eq, Generic, Show)

instance Buildable SelectionReport where
    build = genericF
instance Buildable SelectionReportSummarized where
    build = genericF
instance Buildable SelectionReportDetailed where
    build = genericF

makeSelectionReport :: Selection -> SelectionReport
makeSelectionReport s = SelectionReport
    { summary = makeSelectionReportSummarized s
    , detail = makeSelectionReportDetailed s
    }

makeSelectionReportSummarized :: Selection -> SelectionReportSummarized
makeSelectionReportSummarized s = SelectionReportSummarized {..}
  where
    computedFee
        = selectionDelta TokenBundle.getCoin s
    bccBalanceOfSelectedInputs
        = F.foldMap (view (#tokens . #coin) . snd) $ view #inputs s
    bccBalanceOfExtraCoinSource
        = view #extraCoinSource s
    bccBalanceOfExtraCoinSink
        = view #extraCoinSink s
    bccBalanceOfGeneratedChangeOutputs
        = F.foldMap (view #coin) $ view #change s
    bccBalanceOfRequestedOutputs
        = F.foldMap (view (#tokens . #coin)) $ view #outputs s
    numberOfSelectedInputs
        = length $ view #inputs s
    numberOfSelectedCollateralInputs
        = length $ view #collateral s
    numberOfRequestedOutputs
        = length $ view #outputs s
    numberOfGeneratedChangeOutputs
        = length $ view #change s
    numberOfUniqueNonBccAssetsInSelectedInputs
        = Set.size
        $ F.foldMap (TokenBundle.getAssets . view #tokens . snd)
        $ view #inputs s
    numberOfUniqueNonBccAssetsInRequestedOutputs
        = Set.size
        $ F.foldMap (TokenBundle.getAssets . view #tokens)
        $ view #outputs s
    numberOfUniqueNonBccAssetsInGeneratedChangeOutputs
        = Set.size
        $ F.foldMap TokenBundle.getAssets
        $ view #change s

makeSelectionReportDetailed :: Selection -> SelectionReportDetailed
makeSelectionReportDetailed s = SelectionReportDetailed
    { selectedInputs
        = F.toList $ view #inputs s
    , selectedCollateral
        = F.toList $ view #collateral s
    , requestedOutputs
        = view #outputs s
    , generatedChangeOutputs
        = TokenBundle.Flat <$> view #change s
    }

-- A convenience instance for 'Buildable' contexts that include a nested
-- 'SelectionOf TokenBundle' value.
instance Buildable (SelectionOf TokenBundle) where
    build = build . makeSelectionReport

-- A convenience instance for 'Buildable' contexts that include a nested
-- 'SelectionOf TxOut' value.
instance Buildable (SelectionOf TxOut) where
    build = build
        . makeSelectionReport
        . over #change (fmap $ view #tokens)
