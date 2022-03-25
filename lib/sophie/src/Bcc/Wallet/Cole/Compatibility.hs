{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE TypeFamilies #-}

-- |
-- Copyright: © 2020 IOHK
-- License: Apache-2.0
--
-- Conversion functions and static chain settings for Cole.

module Bcc.Wallet.Cole.Compatibility
    ( -- * Chain Parameters
      mainnetNetworkParameters
    , jenTokenBundleMaxSize

      -- * Genesis
    , emptyGenesis
    , genesisBlockFromTxOuts

      -- * Conversions
    , fromBlockNo
    , fromColeBlock
    , toColeBlockHeader
    , fromColeHash
    , fromChainHash
    , fromGenesisData
    , coleCodecConfig
    , fromProtocolMagicId
    , fromTxAux
    , fromTxIn
    , fromTxOut

    , protocolParametersFromUpdateState
    ) where

import Prelude

import Bcc.Binary
    ( serialize' )
import Bcc.Chain.Block
    ( ABlockOrBoundary (..), blockTxPayload )
import Bcc.Chain.Common
    ( BlockCount (..)
    , Entropic
    , TxFeePolicy (..)
    , TxSizeLinear (..)
    , unsafeGetEntropic
    )
import Bcc.Chain.Genesis
    ( GenesisData (..), GenesisHash (..), GenesisNonAvvmBalances (..) )
import Bcc.Chain.Slotting
    ( EpochSlots (..) )
import Bcc.Chain.Update
    ( ProtocolParameters (..) )
import Bcc.Chain.UTxO
    ( ATxAux (..), Tx (..), TxIn (..), TxOut (..), taTx, unTxPayload )
import Bcc.Crypto
    ( serializeCborHash )
import Bcc.Crypto.ProtocolMagic
    ( ProtocolMagicId, unProtocolMagicId )
import Bcc.Wallet.Unsafe
    ( unsafeFromHex )
import Crypto.Hash.Utils
    ( blake2b256 )
import Data.Coerce
    ( coerce )
import Data.Quantity
    ( Quantity (..) )
import Data.Time.Clock.POSIX
    ( posixSecondsToUTCTime )
import Data.Word
    ( Word16, Word32 )
import Numeric.Natural
    ( Natural )
import Shardagnostic.Consensus.Block.Abstract
    ( headerPrevHash )
import Shardagnostic.Consensus.Cole.Ledger
    ( ColeBlock (..), ColeHash (..) )
import Shardagnostic.Consensus.Cole.Ledger.Config
    ( CodecConfig (..) )
import Shardagnostic.Consensus.HardFork.History.Sumjen
    ( Bound (..) )
import Shardagnostic.Network.Block
    ( BlockNo (..), ChainHash, SlotNo (..) )

import qualified Bcc.Chain.Update as Update
import qualified Bcc.Chain.Update.Validation.Interface as Update
import qualified Bcc.Crypto.Hashing as CC
import qualified Bcc.Wallet.Primitive.Types as W
import qualified Bcc.Wallet.Primitive.Types.Address as W
import qualified Bcc.Wallet.Primitive.Types.Coin as W
import qualified Bcc.Wallet.Primitive.Types.Hash as W
import qualified Bcc.Wallet.Primitive.Types.TokenBundle as TokenBundle
import qualified Bcc.Wallet.Primitive.Types.Tx as W
import qualified Data.ByteString as BS
import qualified Data.List.NonEmpty as NE
import qualified Data.Map.Strict as Map
import qualified Shardagnostic.Consensus.Block as O

--------------------------------------------------------------------------------
--
-- Chain Parameters

mainnetNetworkParameters :: W.NetworkParameters
mainnetNetworkParameters = W.NetworkParameters
    { genesisParameters = W.GenesisParameters
        { getGenesisBlockHash = W.Hash $ unsafeFromHex
            "5f20df933584822601f9e3f8c024eb5eb252fe8cefb24d1317dc3d432e940ebb"
        , getGenesisBlockDate =
            W.StartTime $ posixSecondsToUTCTime 1506203091
        }
    , slottingParameters = W.SlottingParameters
        { getSlotLength =
            W.SlotLength 20
        , getEpochLength =
            W.EpochLength 21600
        , getActiveSlotCoefficient =
            W.ActiveSlotCoefficient 1.0
        , getSecurityParameter =
            Quantity 2160
        }
    , protocolParameters = W.ProtocolParameters
        { decentralizationLevel =
            minBound
        , txParameters = W.TxParameters
            { getFeePolicy =
                W.LinearFee (Quantity 155381) (Quantity 43.946)
            , getTxMaxSize =
                Quantity 4096
            , getTokenBundleMaxSize = jenTokenBundleMaxSize
            }
        , desiredNumberOfStakePools = 0
        , minimumUTxOvalue = W.MinimumUTxOValue $ W.Coin 0
        , stakeKeyDeposit = W.Coin 0
        , eras = W.emptyEraInfo
        , maximumCollateralInputCount = 0
        , executionUnitPrices = Nothing
        }
    }

-- | The max size of token bundles hard-coded in Jen.
--
-- The concept was introduced in Jen, and hard-coded to this value. In Aurum
-- it became an updateable protocol parameter.
--
-- NOTE: A bit weird to define in "Bcc.Wallet.Cole.Compatibility", but we
-- need it both here and in "Bcc.Wallet.Sophie.Compatibility".
jenTokenBundleMaxSize :: W.TokenBundleMaxSize
jenTokenBundleMaxSize = W.TokenBundleMaxSize $ W.TxSize 4000

-- NOTE
-- For MainNet and TestNet, we can get away with empty genesis blocks with
-- the following assumption:
--
-- - Users won't ever restore a wallet that has genesis UTxO.
--
-- This assumption is _true_ for any user using HD wallets (sequential or
-- random) which means, any user of bcc-wallet.
emptyGenesis :: W.GenesisParameters -> W.Block
emptyGenesis gp = W.Block
    { transactions = []
    , delegations  = []
    , header = W.BlockHeader
        { slotNo =
            W.SlotNo 0
        , blockHeight =
            Quantity 0
        , headerHash =
            coerce $ W.getGenesisBlockHash gp
        , parentHeaderHash =
            W.Hash (BS.replicate 32 0)
        }
    }

--------------------------------------------------------------------------------
--
-- Genesis


-- | Construct a ("fake") genesis block from genesis transaction outputs.
--
-- The genesis data on haskell nodes is not a block at all, unlike the block0 on
-- quibitous. This function is a method to deal with the discrepancy.
genesisBlockFromTxOuts :: W.GenesisParameters -> [W.TxOut] -> W.Block
genesisBlockFromTxOuts gp outs = W.Block
    { delegations  = []
    , header = W.BlockHeader
        { slotNo =
            SlotNo 0
        , blockHeight =
            Quantity 0
        , headerHash =
            coerce $ W.getGenesisBlockHash gp
        , parentHeaderHash =
            W.Hash (BS.replicate 32 0)
        }
    , transactions = mkTx <$> outs
    }
  where
    mkTx out@(W.TxOut (W.Address bytes) _) = W.Tx
        { txId = W.Hash $ blake2b256 bytes
        , fee = Nothing
        , resolvedCollateral = []
        , resolvedInputs = []
        , outputs = [out]
        , withdrawals = mempty
        , metadata = Nothing
        , scriptValidity = Nothing
        }

--------------------------------------------------------------------------------
--
-- Type Conversions

toEpochSlots :: W.EpochLength -> EpochSlots
toEpochSlots =
    EpochSlots . fromIntegral . W.unEpochLength

coleCodecConfig :: W.SlottingParameters -> CodecConfig ColeBlock
coleCodecConfig W.SlottingParameters{getEpochLength} =
    ColeCodecConfig (toEpochSlots getEpochLength)

fromColeBlock :: W.GenesisParameters -> ColeBlock -> W.Block
fromColeBlock gp coleBlk = case coleBlockRaw coleBlk of
  ABOBBlock blk  ->
    mkBlock $ fromTxAux <$> unTxPayload (blockTxPayload blk)
  ABOBBoundary _ ->
    mkBlock []
  where
    mkBlock :: [W.Tx] -> W.Block
    mkBlock txs = W.Block
        { header = toColeBlockHeader gp coleBlk
        , transactions = txs
        , delegations  = []
        }

toColeBlockHeader
    :: W.GenesisParameters
    -> ColeBlock
    -> W.BlockHeader
toColeBlockHeader gp blk = W.BlockHeader
    { slotNo =
        O.blockSlot blk
    , blockHeight =
        fromBlockNo $ O.blockNo blk
    , headerHash =
        fromColeHash $ O.blockHash blk
    , parentHeaderHash =
        fromChainHash (W.getGenesisBlockHash gp) $
        headerPrevHash (O.getHeader blk)
    }

fromTxAux :: ATxAux a -> W.Tx
fromTxAux txAux = case taTx txAux of
    tx@(UnsafeTx inputs outputs _attributes) -> W.Tx
        { txId = W.Hash $ CC.hashToBytes $ serializeCborHash tx

        , fee = Nothing

        , resolvedCollateral = []

        -- TODO: Review 'W.Tx' to not require resolved inputs but only inputs
        , resolvedInputs =
            (, W.Coin 0) . fromTxIn <$> NE.toList inputs

        , outputs =
            fromTxOut <$> NE.toList outputs

        , withdrawals =
            mempty

        , metadata =
            Nothing

        , scriptValidity =
            Nothing
        }

fromTxIn :: TxIn -> W.TxIn
fromTxIn (TxInUtxo id_ ix) = W.TxIn
    { inputId = W.Hash $ CC.hashToBytes id_
    , inputIx = ix
    }

fromTxOut :: TxOut -> W.TxOut
fromTxOut (TxOut addr coin) = W.TxOut
    { address = W.Address (serialize' addr)
    , tokens = TokenBundle.fromCoin $ W.Coin $ unsafeGetEntropic coin
    }

fromColeHash :: ColeHash -> W.Hash "BlockHeader"
fromColeHash =
    W.Hash . CC.hashToBytes . unColeHash

fromChainHash :: W.Hash "Genesis" -> ChainHash ColeBlock -> W.Hash "BlockHeader"
fromChainHash genesisHash = \case
    O.GenesisHash -> coerce genesisHash
    O.BlockHash h -> fromColeHash h

-- FIXME unsafe conversion (Word64 -> Word32)
fromBlockNo :: BlockNo -> Quantity "block" Word32
fromBlockNo (BlockNo h) =
    Quantity (fromIntegral h)

fromTxFeePolicy :: TxFeePolicy -> W.FeePolicy
fromTxFeePolicy (TxFeePolicyTxSizeLinear (TxSizeLinear a b)) =
    W.LinearFee
        (Quantity (entropicToDouble a))
        (Quantity (rationalToDouble b))
  where
    entropicToDouble :: Entropic -> Double
    entropicToDouble = fromIntegral . unsafeGetEntropic

    rationalToDouble :: Rational -> Double
    rationalToDouble = fromRational

fromSlotDuration :: Natural -> W.SlotLength
fromSlotDuration =
    W.SlotLength . toEnum . (*1_000_000_000) . fromIntegral

-- NOTE: Unsafe conversion from Word64 -> Word32 here.
--
-- Although... Word64 for `k`? For real?
fromBlockCount :: BlockCount -> W.EpochLength
fromBlockCount (BlockCount k) =
    W.EpochLength (10 * fromIntegral k)

-- NOTE: Unsafe conversion from Natural -> Word16
fromMaxSize :: Natural -> Quantity "byte" Word16
fromMaxSize =
    Quantity . fromIntegral

protocolParametersFromPP
    :: W.EraInfo Bound
    -> Update.ProtocolParameters
    -> W.ProtocolParameters
protocolParametersFromPP eraInfo pp = W.ProtocolParameters
    { decentralizationLevel = minBound
    , txParameters = W.TxParameters
        { getFeePolicy = fromTxFeePolicy $ Update.ppTxFeePolicy pp
        , getTxMaxSize = fromMaxSize $ Update.ppMaxTxSize pp
        , getTokenBundleMaxSize = jenTokenBundleMaxSize
        }
    , desiredNumberOfStakePools = 0
    , minimumUTxOvalue = W.MinimumUTxOValue $ W.Coin 0
    , stakeKeyDeposit = W.Coin 0
    , eras = fromBound <$> eraInfo
    , maximumCollateralInputCount = 0
    , executionUnitPrices = Nothing
    }
  where
    fromBound (Bound _relTime _slotNo (O.EpochNo e)) =
        W.EpochNo $ fromIntegral e

-- | Extract the protocol parameters relevant to the wallet out of the
--   bcc-chain update state record.
protocolParametersFromUpdateState
    :: W.EraInfo Bound
    -> Update.State
    -> W.ProtocolParameters
protocolParametersFromUpdateState b =
    (protocolParametersFromPP b) . Update.adoptedProtocolParameters

-- | Convert non AVVM balances to genesis UTxO.
fromNonAvvmBalances :: GenesisNonAvvmBalances -> [W.TxOut]
fromNonAvvmBalances (GenesisNonAvvmBalances m) =
    fromTxOut . uncurry TxOut <$> Map.toList m

-- | Convert genesis data into blockchain params and an initial set of UTxO
fromGenesisData :: (GenesisData, GenesisHash) -> (W.NetworkParameters, [W.TxOut])
fromGenesisData (genesisData, genesisHash) =
    ( W.NetworkParameters
        { genesisParameters = W.GenesisParameters
            { getGenesisBlockHash =
                W.Hash . CC.hashToBytes . unGenesisHash $ genesisHash
            , getGenesisBlockDate =
                W.StartTime . gdStartTime $ genesisData
            }
        , slottingParameters = W.SlottingParameters
            { getSlotLength =
                fromSlotDuration . ppSlotDuration . gdProtocolParameters $ genesisData
            , getEpochLength =
                fromBlockCount . gdK $ genesisData
            , getActiveSlotCoefficient =
                W.ActiveSlotCoefficient 1.0
            , getSecurityParameter =
                Quantity . fromIntegral . unBlockCount . gdK $ genesisData
            }
        , protocolParameters =
            -- emptyEraInfo contains no info about cole. Should we add it?
            (protocolParametersFromPP W.emptyEraInfo) . gdProtocolParameters $ genesisData
        }
    , fromNonAvvmBalances . gdNonAvvmBalances $ genesisData
    )

fromProtocolMagicId :: ProtocolMagicId -> W.ProtocolMagic
fromProtocolMagicId = W.ProtocolMagic . fromIntegral . unProtocolMagicId
