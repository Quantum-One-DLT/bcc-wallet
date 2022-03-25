{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE TypeApplications #-}

module Bcc.Wallet.Primitive.CoinSelection.Gen
    ( genSelectionLimit
    , genSelectionSkeleton
    , shrinkSelectionLimit
    , shrinkSelectionSkeleton
    )
    where

import Prelude

import Bcc.Wallet.Primitive.CoinSelection.Balance
    ( SelectionLimit, SelectionLimitOf (..), SelectionSkeleton (..) )
import Bcc.Wallet.Primitive.Types.TokenMap.Gen
    ( genAssetId, genTokenMap, shrinkAssetId, shrinkTokenMap )
import Bcc.Wallet.Primitive.Types.Tx.Gen
    ( genTxOut, shrinkTxOut )
import Test.QuickCheck
    ( Gen
    , NonNegative (..)
    , arbitrary
    , listOf
    , oneof
    , shrink
    , shrinkList
    , shrinkMapBy
    )
import Test.QuickCheck.Extra
    ( liftShrink5 )

import qualified Data.Set as Set

--------------------------------------------------------------------------------
-- Selection limits
--------------------------------------------------------------------------------

genSelectionLimit :: Gen SelectionLimit
genSelectionLimit = oneof
    [ MaximumInputLimit . getNonNegative <$> arbitrary
    , pure NoLimit
    ]

shrinkSelectionLimit :: SelectionLimit -> [SelectionLimit]
shrinkSelectionLimit = \case
    MaximumInputLimit n ->
        MaximumInputLimit . getNonNegative <$> shrink (NonNegative n)
    NoLimit ->
        []

--------------------------------------------------------------------------------
-- Selection skeletons
--------------------------------------------------------------------------------

genSelectionSkeleton :: Gen SelectionSkeleton
genSelectionSkeleton = SelectionSkeleton
    <$> genSkeletonInputCount
    <*> genSkeletonOutputs
    <*> genSkeletonChange
    <*> genSkeletonAssetsToMint
    <*> genSkeletonAssetsToBurn
  where
    genSkeletonInputCount =
        getNonNegative <$> arbitrary @(NonNegative Int)
    genSkeletonOutputs =
        listOf genTxOut
    genSkeletonChange =
        listOf (Set.fromList <$> listOf genAssetId)
    genSkeletonAssetsToMint =
        genTokenMap
    genSkeletonAssetsToBurn =
        genTokenMap

shrinkSelectionSkeleton :: SelectionSkeleton -> [SelectionSkeleton]
shrinkSelectionSkeleton =
    shrinkMapBy tupleToSkeleton skeletonToTuple $ liftShrink5
        shrinkSkeletonInputCount
        shrinkSkeletonOutputs
        shrinkSkeletonChange
        shrinkSkeletonAssetsToMint
        shrinkSkeletonAssetsToBurn
  where
    shrinkSkeletonInputCount =
        shrink @Int
    shrinkSkeletonOutputs =
        shrinkList shrinkTxOut
    shrinkSkeletonChange =
        shrinkList $
        shrinkMapBy Set.fromList Set.toList (shrinkList shrinkAssetId)
    shrinkSkeletonAssetsToMint =
        shrinkTokenMap
    shrinkSkeletonAssetsToBurn =
        shrinkTokenMap

    skeletonToTuple (SelectionSkeleton a b c d e) = (a, b, c, d, e)
    tupleToSkeleton (a, b, c, d, e) = (SelectionSkeleton a b c d e)
