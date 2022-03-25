{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

module Bcc.Wallet.Primitive.AddressDiscoverySpec
    ( spec
    ) where

import Prelude

import Bcc.Address.Derivation
    ( XPrv )
import Bcc.Mnemonic
    ( SomeMnemonic (..) )
import Bcc.Wallet.Gen
    ( genMnemonic )
import Bcc.Wallet.Primitive.AddressDerivation
    ( Depth (AccountK, AddressK, RootK)
    , DerivationType (..)
    , Index
    , NetworkDiscriminant (..)
    , Passphrase (..)
    , PaymentAddress (..)
    , passphraseMaxLength
    , passphraseMinLength
    , publicKey
    )
import Bcc.Wallet.Primitive.AddressDerivation.Cole
    ( ColeKey, generateKeyFromSeed, unsafeGenerateKeyFromSeed )
import Bcc.Wallet.Primitive.AddressDiscovery
    ( IsOurs (..), knownAddresses )
import Bcc.Wallet.Primitive.AddressDiscovery.Random
    ( mkRndState )
import Control.Monad
    ( replicateM )
import Data.Maybe
    ( isJust, isNothing )
import Data.Proxy
    ( Proxy (..) )
import Test.Hspec
    ( Spec, describe, it )
import Test.Hspec.Extra
    ( parallel )
import Test.QuickCheck
    ( Arbitrary (..)
    , Gen
    , InfiniteList (..)
    , Property
    , arbitraryBoundedEnum
    , arbitraryPrintableChar
    , choose
    , property
    , (.&&.)
    )

import qualified Bcc.Crypto.Wallet as CC
import qualified Data.ByteArray as BA
import qualified Data.ByteString as BS
import qualified Data.Text as T
import qualified Data.Text.Encoding as T

spec :: Spec
spec = do
    parallel $ describe "Random Address Discovery Properties" $ do
        it "isOurs works as expected during key derivation in testnet" $ do
            property (prop_derivedKeysAreOurs @('Testnet 0))
        it "isOurs works as expected during key derivation in mainnet" $ do
            property (prop_derivedKeysAreOurs @'Mainnet)

{-------------------------------------------------------------------------------
                               Properties
-------------------------------------------------------------------------------}

prop_derivedKeysAreOurs
    :: forall (n :: NetworkDiscriminant). (PaymentAddress n ColeKey)
    => SomeMnemonic
    -> Passphrase "encryption"
    -> Index 'WholeDomain 'AccountK
    -> Index 'WholeDomain 'AddressK
    -> ColeKey 'RootK XPrv
    -> Property
prop_derivedKeysAreOurs seed encPwd accIx addrIx rk' =
    isJust resPos .&&. addr `elem` (fst' <$> knownAddresses stPos') .&&.
    isNothing resNeg .&&. addr `notElem` (fst' <$> knownAddresses stNeg')
  where
    fst' (a,_,_) = a
    (resPos, stPos') = isOurs addr (mkRndState @n rootXPrv 0)
    (resNeg, stNeg') = isOurs addr (mkRndState @n rk' 0)
    key = publicKey $ unsafeGenerateKeyFromSeed (accIx, addrIx) seed encPwd
    rootXPrv = generateKeyFromSeed seed encPwd
    addr = paymentAddress @n key

{-------------------------------------------------------------------------------
                             Arbitrary Instances
-------------------------------------------------------------------------------}

instance Arbitrary (Index 'WholeDomain 'AccountK) where
    shrink _ = []
    arbitrary = arbitraryBoundedEnum

instance Arbitrary (Index 'WholeDomain 'AddressK) where
    shrink _ = []
    arbitrary = arbitraryBoundedEnum

instance Arbitrary (ColeKey 'RootK XPrv) where
    shrink _ = []
    arbitrary = genRootKeys

genRootKeys :: Gen (ColeKey 'RootK XPrv)
genRootKeys = do
    mnemonic <- arbitrary
    e <- genPassphrase @"encryption" (0, 16)
    return $ generateKeyFromSeed mnemonic e
  where
    genPassphrase :: (Int, Int) -> Gen (Passphrase purpose)
    genPassphrase range = do
        n <- choose range
        InfiniteList bytes _ <- arbitrary
        return $ Passphrase $ BA.convert $ BS.pack $ take n bytes

instance Show XPrv where
    show = show . CC.unXPrv

instance {-# OVERLAPS #-} Arbitrary (Passphrase "encryption") where
    arbitrary = do
        let p = Proxy :: Proxy "raw"
        n <- choose (passphraseMinLength p, passphraseMaxLength p)
        bytes <- T.encodeUtf8 . T.pack <$> replicateM n arbitraryPrintableChar
        return $ Passphrase $ BA.convert bytes

instance Arbitrary SomeMnemonic where
    arbitrary = SomeMnemonic <$> genMnemonic @12