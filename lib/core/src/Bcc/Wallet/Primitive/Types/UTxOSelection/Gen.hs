{-# LANGUAGE TypeApplications #-}

module Bcc.Wallet.Primitive.Types.UTxOSelection.Gen
    ( genUTxOSelection
    , genUTxOSelectionNonEmpty
    , shrinkUTxOSelection
    , shrinkUTxOSelectionNonEmpty
    )
    where

import Prelude

import Bcc.Wallet.Primitive.Types.Tx
    ( TxIn )
import Bcc.Wallet.Primitive.Types.Tx.Gen
    ( genTxInFunction )
import Bcc.Wallet.Primitive.Types.UTxOIndex.Gen
    ( genUTxOIndex, shrinkUTxOIndex )
import Bcc.Wallet.Primitive.Types.UTxOSelection
    ( UTxOSelection, UTxOSelectionNonEmpty )
import Data.Maybe
    ( mapMaybe )
import Test.QuickCheck
    ( Gen, arbitrary, liftShrink2, shrinkMapBy, suchThatMap )

import qualified Bcc.Wallet.Primitive.Types.UTxOSelection as UTxOSelection

--------------------------------------------------------------------------------
-- Selections that may be empty
--------------------------------------------------------------------------------

genUTxOSelection :: Gen UTxOSelection
genUTxOSelection = UTxOSelection.fromIndexFiltered
    <$> genFilter
    <*> genUTxOIndex
  where
    genFilter :: Gen (TxIn -> Bool)
    genFilter = genTxInFunction (arbitrary @Bool)

shrinkUTxOSelection :: UTxOSelection -> [UTxOSelection]
shrinkUTxOSelection =
    shrinkMapBy UTxOSelection.fromIndexPair UTxOSelection.toIndexPair $
        liftShrink2
            shrinkUTxOIndex
            shrinkUTxOIndex

--------------------------------------------------------------------------------
-- Selections that are non-empty
--------------------------------------------------------------------------------

genUTxOSelectionNonEmpty :: Gen UTxOSelectionNonEmpty
genUTxOSelectionNonEmpty =
    genUTxOSelection `suchThatMap` UTxOSelection.toNonEmpty

shrinkUTxOSelectionNonEmpty :: UTxOSelectionNonEmpty -> [UTxOSelectionNonEmpty]
shrinkUTxOSelectionNonEmpty
    = mapMaybe UTxOSelection.toNonEmpty
    . shrinkUTxOSelection
    . UTxOSelection.fromNonEmpty

