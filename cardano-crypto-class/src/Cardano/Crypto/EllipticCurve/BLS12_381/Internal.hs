{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE FlexibleContexts #-}

module Cardano.Crypto.EllipticCurve.BLS12_381.Internal
(
  -- * Unsafe Types
    ScalarPtr
  , FrPtr
  , FPPtr
  , PPtr
  , AffinePtr

  , P1Ptr
  , P2Ptr
  , Affine1Ptr
  , Affine2Ptr

  -- * Phantom Types
  , Curve1
  , Curve2

  -- * Error codes
  , c_blst_success
  , c_blst_error_bad_encoding
  , c_blst_error_point_not_on_curve
  , c_blst_error_point_not_in_group
  , c_blst_error_aggr_type_mismatch
  , c_blst_error_verify_fail
  , c_blst_error_pk_is_infinity
  , c_blst_error_bad_scalar

  -- * Safe types
  , Affine
  , Affine1
  , Affine2
  , BLSTError (..)
  , FP
  , Fr
  , P
  , P1
  , P2
  , Scalar

  , unsafePFromPPtr

  -- * Curve abstraction

  , BLS

  , BLS_Curve
      ( c_blst_on_curve
      , c_blst_add
      , c_blst_mult
      , c_blst_cneg
      , c_blst_hash
      , c_blst_compress
      , c_blst_serialize
      , c_blst_uncompress
      , c_blst_deserialize
      , c_blst_in_g
      , c_blst_to_affine
      , c_blst_from_affine
      , c_blst_affine_in_g
      , c_blst_generator
      , c_blst_x_from_p
      , c_blst_y_from_p
      , c_blst_z_from_p
      , c_blst_x_from_affine
      , c_blst_y_from_affine
      , c_blst_p_is_equal
      , c_blst_p_is_inf
      )

  -- * Pairing check

  , c_blst_two_miller_one_exp

  -- * Scalar functions

  , c_blst_fr_add
  , c_blst_fr_mul
  , c_blst_fr_inverse
  , c_blst_fr_cneg
  , c_blst_fr_sqr
  , c_blst_scalar_fr_check

  , c_blst_scalar_from_fr
  , c_blst_fr_from_scalar
  , c_blst_scalar_from_be_bytes
  , c_blst_bendian_from_scalar

  -- * Marshalling functions
  , BLS_P
  , sizeP
  , withP
  , withNewP
  , withNewP_
  , withNewP'
  , cloneP
  , compressedSizeP
  , serializedSizeP

  , sizeAffine
  , withAffine
  , withNewAffine
  , withNewAffine_
  , withNewAffine'

  , sizeScalar
  , withScalar
  , withNewScalar
  , withNewScalar_
  , withNewScalar'
  , cloneScalar
  , scalarToNat
  , scalarFromNat

  , sizeFP
  , withFP
  , withNewFP
  , withNewFP_
  , withNewFP'
  , cloneFP
  , fpToNat

  , sizeFr
  , withFr
  , withNewFr
  , withNewFr_
  , withNewFr'
  , cloneFr

  -- * Utility
  , natAsCStr
  , cstrToNat
  , natToBS

  -- * P1/G1 operations
  , onCurve
  , add
  , mult
  , cneg
  , neg
  , compress
  , serialize
  , uncompress
  , deserialize
  , hash
  , generator
  , isInf

  , toXYZ
  , toXY

  , toAffine
  , fromAffine
  , affineInG

  -- * Scalar / Fr operations
  , scalarFromFr
  , frFromScalar
  , frFromCanonicalScalar
  , scalarFromBS
  , scalarToBS
  , scalarFromNatural
  , scalarToNatural
  , scalarCanonical

  , frAdd
  , frMult
  , frNeg
  , frInverse
  , frSqr
  , frFromNatural
  , frToNatural

  -- * Pairings
  , pairingCheck
)
where

import Data.Bits (shiftL, shiftR, (.|.))
import Data.ByteString (ByteString)
import Data.Proxy (Proxy (..))
import Data.Void
import Foreign.C.String
import Foreign.C.Types
import Foreign.ForeignPtr
import Foreign.Marshal.Alloc (allocaBytes)
import Foreign.Marshal.Utils (copyBytes)
import Foreign.Ptr (Ptr, nullPtr, castPtr, plusPtr)
import Foreign.Storable (peek)
import Numeric.Natural
import qualified Data.ByteString as BS
import System.IO.Unsafe (unsafePerformIO)

---- Phantom Types

data Curve1
data Curve2

---- Unsafe PPtr types

newtype PPtr curve = PPtr (Ptr Void)

type P1Ptr = PPtr Curve1
type P2Ptr = PPtr Curve2

newtype AffinePtr curve = AffinePtr (Ptr Void)

type Affine1Ptr = AffinePtr Curve1
type Affine2Ptr = AffinePtr Curve2

unsafePFromPPtr :: PPtr curve -> P curve
unsafePFromPPtr (PPtr ptr) =
  P . unsafePerformIO $ newForeignPtr_ ptr

eqAffinePtr :: forall curve. BLS_P curve => AffinePtr curve -> AffinePtr curve -> IO Bool
eqAffinePtr (AffinePtr a) (AffinePtr b) =
  (== 0) <$> c_memcmp (castPtr a) (castPtr b) (sizeAffine  (Proxy @curve))

instance BLS_P curve => Eq (AffinePtr curve) where
  a == b = unsafePerformIO $ eqAffinePtr a b

---- Safe P types / marshalling

newtype P curve = P (ForeignPtr Void)

type P1 = P Curve1
type P2 = P Curve2

newtype Affine curve = Affine (ForeignPtr Void)

type Affine1 = Affine Curve1
type Affine2 = Affine Curve2

instance BLS_P curve => Eq (Affine curve) where
  a == b = unsafePerformIO $
    withAffine a $ \aptr ->
      withAffine b $ \bptr ->
        eqAffinePtr aptr bptr

class BLS_P curve where
  _sizeP :: Proxy curve -> CSize
  _compressedSizeP :: Proxy curve -> CSize
  _serializedSizeP :: Proxy curve -> CSize
  _sizeAffine :: Proxy curve -> CSize

sizeP :: forall curve i. (BLS_P curve, Num i) => Proxy curve -> i
sizeP p = fromIntegral $ _sizeP p

compressedSizeP :: forall curve i. (BLS_P curve, Num i) => Proxy curve -> i
compressedSizeP = fromIntegral . _compressedSizeP

serializedSizeP :: forall curve i. (BLS_P curve, Num i) => Proxy curve -> i
serializedSizeP = fromIntegral . _serializedSizeP

sizeAffine :: forall curve i. (BLS_P curve, Num i) => Proxy curve -> i
sizeAffine = fromIntegral . _sizeAffine

withP :: forall a curve. P curve -> (PPtr curve -> IO a) -> IO a
withP (P p) go = withForeignPtr p (go . PPtr)

withNewP :: forall curve a. (BLS_P curve) => (PPtr curve -> IO a) -> IO (a, P curve)
withNewP go = do
  p <- mallocForeignPtrBytes (sizeP (Proxy @curve))
  x <- withForeignPtr p (go . PPtr)
  return (x, P p)

withNewP_ :: (BLS_P curve) => (PPtr curve -> IO a) -> IO a
withNewP_ = fmap fst . withNewP

withNewP' :: (BLS_P curve) => (PPtr curve -> IO a) -> IO (P curve)
withNewP' = fmap snd . withNewP

cloneP :: forall curve. (BLS_P curve) => P curve -> IO (P curve)
cloneP (P a) = do
  b <- mallocForeignPtrBytes (sizeP (Proxy @curve))
  withForeignPtr a $ \ap ->
    withForeignPtr b $ \bp ->
      copyBytes bp ap (sizeP (Proxy @curve))
  return (P b)

withAffine :: forall a curve. Affine curve -> (AffinePtr curve -> IO a) -> IO a
withAffine (Affine p) go = withForeignPtr p (go . AffinePtr)

withNewAffine :: forall curve a. (BLS_P curve) => (AffinePtr curve -> IO a) -> IO (a, Affine curve)
withNewAffine go = do
  p <- mallocForeignPtrBytes (sizeAffine (Proxy @curve))
  x <- withForeignPtr p (go . AffinePtr)
  return (x, Affine p)

withNewAffine_ :: (BLS_P curve) => (AffinePtr curve -> IO a) -> IO a
withNewAffine_ = fmap fst . withNewAffine

withNewAffine' :: (BLS_P curve) => (AffinePtr curve -> IO a) -> IO (Affine curve)
withNewAffine' = fmap snd . withNewAffine

instance BLS_P Curve1 where
  _sizeP _ = fromIntegral c_size_blst_p1
  _compressedSizeP _ = 48
  _serializedSizeP _ = 96
  _sizeAffine _ = fromIntegral c_size_blst_affine1

instance BLS_P Curve2 where
  _sizeP _ = fromIntegral c_size_blst_p2
  _compressedSizeP _ = 96
  _serializedSizeP _ = 192
  _sizeAffine _ = fromIntegral c_size_blst_affine2


---- Curve operations

class BLS_Curve curve where
  c_blst_on_curve :: PPtr curve -> IO Bool

  c_blst_add :: PPtr curve -> PPtr curve -> PPtr curve -> IO ()
  c_blst_mult :: PPtr curve -> PPtr curve -> ScalarPtr -> CInt -> IO ()
  c_blst_cneg :: PPtr curve -> Bool -> IO ()

  c_blst_hash :: PPtr curve -> Ptr CChar -> CSize -> Ptr CChar -> CSize -> Ptr CChar -> CSize -> IO ()
  c_blst_compress :: Ptr CChar -> PPtr curve -> IO ()
  c_blst_serialize :: Ptr CChar -> PPtr curve -> IO ()
  c_blst_uncompress :: AffinePtr curve -> Ptr CChar -> IO CInt
  c_blst_deserialize :: AffinePtr curve -> Ptr CChar -> IO CInt

  c_blst_in_g :: PPtr curve -> IO Bool
  c_blst_to_affine :: AffinePtr curve -> PPtr curve -> IO ()
  c_blst_from_affine :: PPtr curve -> AffinePtr curve -> IO ()
  c_blst_affine_in_g :: AffinePtr curve -> IO Bool
  c_blst_generator :: PPtr curve

  c_blst_x_from_p :: FPPtr -> PPtr curve -> IO ()
  c_blst_y_from_p :: FPPtr -> PPtr curve -> IO ()
  c_blst_z_from_p :: FPPtr -> PPtr curve -> IO ()

  c_blst_x_from_affine :: FPPtr -> AffinePtr curve -> IO ()
  c_blst_y_from_affine :: FPPtr -> AffinePtr curve -> IO ()
  c_blst_p_is_equal :: PPtr curve -> PPtr curve -> IO Bool
  c_blst_p_is_inf :: PPtr curve -> IO Bool

instance BLS_Curve Curve1 where
  c_blst_on_curve = c_blst_p1_on_curve

  c_blst_add = c_blst_p1_add
  c_blst_mult = c_blst_p1_mult
  c_blst_cneg = c_blst_p1_cneg

  c_blst_hash = c_blst_hash_to_g1
  c_blst_compress = c_blst_p1_compress
  c_blst_serialize = c_blst_p1_serialize
  c_blst_uncompress = c_blst_p1_uncompress
  c_blst_deserialize = c_blst_p1_deserialize

  c_blst_in_g = c_blst_p1_in_g1
  c_blst_to_affine = c_blst_p1_to_affine
  c_blst_from_affine = c_blst_p1_from_affine
  c_blst_affine_in_g = c_blst_p1_affine_in_g1

  c_blst_generator = c_blst_p1_generator

  c_blst_x_from_p = c_blst_x_from_p1
  c_blst_y_from_p = c_blst_y_from_p1
  c_blst_z_from_p = c_blst_z_from_p1

  c_blst_x_from_affine = c_blst_x_from_affine1
  c_blst_y_from_affine = c_blst_y_from_affine1
  c_blst_p_is_equal = c_blst_p1_is_equal
  c_blst_p_is_inf = c_blst_p1_is_inf

instance BLS_Curve Curve2 where
  c_blst_on_curve = c_blst_p2_on_curve

  c_blst_add = c_blst_p2_add
  c_blst_mult = c_blst_p2_mult
  c_blst_cneg = c_blst_p2_cneg

  c_blst_hash = c_blst_hash_to_g2
  c_blst_compress = c_blst_p2_compress
  c_blst_serialize = c_blst_p2_serialize
  c_blst_uncompress = c_blst_p2_uncompress
  c_blst_deserialize = c_blst_p2_deserialize

  c_blst_in_g = c_blst_p2_in_g2
  c_blst_to_affine = c_blst_p2_to_affine
  c_blst_from_affine = c_blst_p2_from_affine
  c_blst_affine_in_g = c_blst_p2_affine_in_g2

  c_blst_generator = c_blst_p2_generator

  c_blst_x_from_p = c_blst_x_from_p2
  c_blst_y_from_p = c_blst_y_from_p2
  c_blst_z_from_p = c_blst_z_from_p2

  c_blst_x_from_affine = c_blst_x_from_affine2
  c_blst_y_from_affine = c_blst_y_from_affine2

  c_blst_p_is_equal = c_blst_p2_is_equal
  c_blst_p_is_inf = c_blst_p2_is_inf

---- Safe Scalar types / marshalling

sizeScalar :: forall i. Num i => i
sizeScalar = fromIntegral c_size_blst_scalar

newtype Scalar = Scalar (ForeignPtr Void)

withScalar :: Scalar -> (ScalarPtr -> IO a) -> IO a
withScalar (Scalar p2) go = do
  withForeignPtr p2 (go . ScalarPtr)

withNewScalar :: (ScalarPtr -> IO a) -> IO (a, Scalar)
withNewScalar go = do
  p2 <- mallocForeignPtrBytes sizeScalar
  x <- withForeignPtr p2 (go . ScalarPtr)
  return (x, Scalar p2)

withNewScalar_ :: (ScalarPtr -> IO a) -> IO a
withNewScalar_ = fmap fst . withNewScalar

withNewScalar' :: (ScalarPtr -> IO a) -> IO Scalar
withNewScalar' = fmap snd . withNewScalar

cloneScalar :: Scalar -> IO Scalar
cloneScalar (Scalar a) = do
  b <- mallocForeignPtrBytes sizeScalar
  withForeignPtr a $ \ap ->
    withForeignPtr b $ \bp ->
      copyBytes bp ap sizeScalar
  return (Scalar b)

sizeFr :: forall i. Num i => i
sizeFr = fromIntegral c_size_blst_fr

newtype Fr = Fr (ForeignPtr Void)

withFr :: Fr -> (FrPtr -> IO a) -> IO a
withFr (Fr p2) go = do
  withForeignPtr p2 (go . FrPtr)

withNewFr :: (FrPtr -> IO a) -> IO (a, Fr)
withNewFr go = do
  p2 <- mallocForeignPtrBytes sizeFr
  x <- withForeignPtr p2 (go . FrPtr)
  return (x, Fr p2)

withNewFr_ :: (FrPtr -> IO a) -> IO a
withNewFr_ = fmap fst . withNewFr

withNewFr' :: (FrPtr -> IO a) -> IO Fr
withNewFr' = fmap snd . withNewFr

cloneFr :: Fr -> IO Fr
cloneFr (Fr a) = do
  b <- mallocForeignPtrBytes sizeFr
  withForeignPtr a $ \ap ->
    withForeignPtr b $ \bp ->
      copyBytes bp ap sizeFr
  return (Fr b)

---- Safe FP types / marshalling

sizeFP :: forall i. Num i => i
sizeFP = fromIntegral c_size_blst_scalar

newtype FP = FP (ForeignPtr Void)

withFP :: FP -> (FPPtr -> IO a) -> IO a
withFP (FP p2) go = do
  withForeignPtr p2 (go . FPPtr)

withNewFP :: (FPPtr -> IO a) -> IO (a, FP)
withNewFP go = do
  p2 <- mallocForeignPtrBytes sizeFP
  x <- withForeignPtr p2 (go . FPPtr)
  return (x, FP p2)

withNewFP_ :: (FPPtr -> IO a) -> IO a
withNewFP_ = fmap fst . withNewFP

withNewFP' :: (FPPtr -> IO a) -> IO FP
withNewFP' = fmap snd . withNewFP

cloneFP :: FP -> IO FP
cloneFP (FP a) = do
  b <- mallocForeignPtrBytes sizeFP
  withForeignPtr a $ \ap ->
    withForeignPtr b $ \bp ->
      copyBytes bp ap sizeFP
  return (FP b)

fpToNat :: FP -> IO Natural
fpToNat fp = withFP fp $ \fpPtr -> do
  allocaBytes 48 $ \rawPtr -> do
    c_blst_bendian_from_fp rawPtr fpPtr
    cstrToNat rawPtr 48

scalarToNat :: Scalar -> IO Natural
scalarToNat scalar = withScalar scalar $ \scalarPtr -> do
  allocaBytes sizeScalar $ \rawPtr -> do
    c_blst_bendian_from_scalar rawPtr scalarPtr
    cstrToNat rawPtr sizeScalar

cstrToNat :: Ptr CChar -> Int -> IO Natural
cstrToNat p l = do
  go l (castPtr p)
  where
    go :: Int -> Ptr CUChar -> IO Natural
    go 0 _ = return 0
    go n ptr = do
      val <- peek ptr
      res <- go (pred n) (plusPtr ptr 1)
      return $ shiftL res 8 .|. fromIntegral val

natToBS :: Natural -> ByteString
natToBS 0 = BS.empty
natToBS n =
  BS.snoc
    (natToBS (n `shiftR` 8))
    (fromIntegral n)

padBS :: Int -> ByteString -> ByteString
padBS i b
  | i > BS.length b
  = BS.replicate (i - BS.length b) 0 <> b
  | otherwise
  = b

natAsCStr :: Natural -> (Ptr CChar -> Int -> IO a) -> IO a
natAsCStr n f = do
  let bs = natToBS n
  BS.useAsCStringLen bs $ uncurry f

natAsCStrL :: Int -> Natural -> (Ptr CChar -> Int -> IO a) -> IO a
natAsCStrL i n f = do
  let bs = padBS i $ natToBS n
  BS.useAsCStringLen bs $ uncurry f

scalarFromNat :: Natural -> IO Scalar
scalarFromNat n = do
  withNewScalar' $ \scalarPtr -> do
    natAsCStrL 32 n $ \str _length -> do
      c_blst_scalar_from_bendian scalarPtr str

---- Unsafe types

newtype ScalarPtr = ScalarPtr (Ptr Void)
newtype FrPtr = FrPtr (Ptr Void)
newtype FPPtr = FPPtr (Ptr Void)

---- Raw Scalar / Fr functions

foreign import ccall "size_blst_scalar" c_size_blst_scalar :: CSize
foreign import ccall "size_blst_fr" c_size_blst_fr :: CSize

foreign import ccall "blst_fr_add" c_blst_fr_add :: FrPtr -> FrPtr -> FrPtr -> IO ()
foreign import ccall "blst_fr_mul" c_blst_fr_mul :: FrPtr -> FrPtr -> FrPtr -> IO ()
foreign import ccall "blst_fr_inverse" c_blst_fr_inverse :: FrPtr -> FrPtr -> IO ()
foreign import ccall "blst_fr_cneg" c_blst_fr_cneg :: FrPtr -> FrPtr -> IO ()
foreign import ccall "blst_fr_sqr" c_blst_fr_sqr :: FrPtr -> FrPtr -> IO ()
foreign import ccall "blst_scalar_fr_check" c_blst_scalar_fr_check :: ScalarPtr -> IO Bool

foreign import ccall "blst_scalar_from_fr" c_blst_scalar_from_fr :: ScalarPtr -> FrPtr -> IO ()
foreign import ccall "blst_fr_from_scalar" c_blst_fr_from_scalar :: FrPtr -> ScalarPtr -> IO ()
foreign import ccall "blst_scalar_from_be_bytes" c_blst_scalar_from_be_bytes :: ScalarPtr -> Ptr CChar -> CSize -> IO Bool
foreign import ccall "blst_scalar_from_bendian" c_blst_scalar_from_bendian :: ScalarPtr -> Ptr CChar -> IO ()

---- Raw P1 functions

foreign import ccall "size_blst_p1" c_size_blst_p1 :: CSize
foreign import ccall "blst_p1_on_curve" c_blst_p1_on_curve :: P1Ptr -> IO Bool

foreign import ccall "blst_p1_add_or_double" c_blst_p1_add :: P1Ptr -> P1Ptr -> P1Ptr -> IO ()
foreign import ccall "blst_p1_mult" c_blst_p1_mult :: P1Ptr -> P1Ptr -> ScalarPtr -> CInt -> IO ()
foreign import ccall "blst_p1_cneg" c_blst_p1_cneg :: P1Ptr -> Bool -> IO ()

foreign import ccall "blst_hash_to_g1" c_blst_hash_to_g1 :: P1Ptr -> Ptr CChar -> CSize -> Ptr CChar -> CSize -> Ptr CChar -> CSize -> IO ()
foreign import ccall "blst_p1_compress" c_blst_p1_compress :: Ptr CChar -> P1Ptr -> IO ()
foreign import ccall "blst_p1_serialize" c_blst_p1_serialize :: Ptr CChar -> P1Ptr -> IO ()
foreign import ccall "blst_p1_uncompress" c_blst_p1_uncompress :: Affine1Ptr -> Ptr CChar -> IO CInt
foreign import ccall "blst_p1_deserialize" c_blst_p1_deserialize :: Affine1Ptr -> Ptr CChar -> IO CInt

foreign import ccall "blst_p1_in_g1" c_blst_p1_in_g1 :: P1Ptr -> IO Bool

foreign import ccall "blst_p1_generator" c_blst_p1_generator :: P1Ptr

foreign import ccall "blst_x_from_p1" c_blst_x_from_p1 :: FPPtr -> P1Ptr -> IO ()
foreign import ccall "blst_y_from_p1" c_blst_y_from_p1 :: FPPtr -> P1Ptr -> IO ()
foreign import ccall "blst_z_from_p1" c_blst_z_from_p1 :: FPPtr -> P1Ptr -> IO ()

foreign import ccall "blst_x_from_affine1" c_blst_x_from_affine1 :: FPPtr -> Affine1Ptr -> IO ()
foreign import ccall "blst_y_from_affine1" c_blst_y_from_affine1 :: FPPtr -> Affine1Ptr -> IO ()

foreign import ccall "blst_p1_is_equal" c_blst_p1_is_equal :: P1Ptr -> P1Ptr -> IO Bool
foreign import ccall "blst_p1_is_inf" c_blst_p1_is_inf :: P1Ptr -> IO Bool

---- Raw P2 functions

foreign import ccall "size_blst_p2" c_size_blst_p2 :: CSize
foreign import ccall "blst_p2_on_curve" c_blst_p2_on_curve :: P2Ptr -> IO Bool

foreign import ccall "blst_p2_add_or_double" c_blst_p2_add :: P2Ptr -> P2Ptr -> P2Ptr -> IO ()
foreign import ccall "blst_p2_mult" c_blst_p2_mult :: P2Ptr -> P2Ptr -> ScalarPtr -> CInt -> IO ()
foreign import ccall "blst_p2_cneg" c_blst_p2_cneg :: P2Ptr -> Bool -> IO ()

foreign import ccall "blst_hash_to_g2" c_blst_hash_to_g2 :: P2Ptr -> Ptr CChar -> CSize -> Ptr CChar -> CSize -> Ptr CChar -> CSize -> IO ()
foreign import ccall "blst_p2_compress" c_blst_p2_compress :: Ptr CChar -> P2Ptr -> IO ()
foreign import ccall "blst_p2_serialize" c_blst_p2_serialize :: Ptr CChar -> P2Ptr -> IO ()
foreign import ccall "blst_p2_uncompress" c_blst_p2_uncompress :: Affine2Ptr -> Ptr CChar -> IO CInt
foreign import ccall "blst_p2_deserialize" c_blst_p2_deserialize :: Affine2Ptr -> Ptr CChar -> IO CInt

foreign import ccall "blst_p2_in_g2" c_blst_p2_in_g2 :: P2Ptr -> IO Bool

foreign import ccall "blst_p2_generator" c_blst_p2_generator :: P2Ptr

foreign import ccall "blst_x_from_p2" c_blst_x_from_p2 :: FPPtr -> P2Ptr -> IO ()
foreign import ccall "blst_y_from_p2" c_blst_y_from_p2 :: FPPtr -> P2Ptr -> IO ()
foreign import ccall "blst_z_from_p2" c_blst_z_from_p2 :: FPPtr -> P2Ptr -> IO ()

foreign import ccall "blst_x_from_affine2" c_blst_x_from_affine2 :: FPPtr -> Affine2Ptr -> IO ()
foreign import ccall "blst_y_from_affine2" c_blst_y_from_affine2 :: FPPtr -> Affine2Ptr -> IO ()

foreign import ccall "blst_p2_is_equal" c_blst_p2_is_equal :: P2Ptr -> P2Ptr -> IO Bool
foreign import ccall "blst_p2_is_inf" c_blst_p2_is_inf :: P2Ptr -> IO Bool

---- Affine operations

foreign import ccall "size_blst_affine1" c_size_blst_affine1 :: CSize
foreign import ccall "size_blst_affine2" c_size_blst_affine2 :: CSize

foreign import ccall "blst_p1_to_affine" c_blst_p1_to_affine :: AffinePtr Curve1 -> PPtr Curve1 -> IO ()
foreign import ccall "blst_p2_to_affine" c_blst_p2_to_affine :: AffinePtr Curve2 -> PPtr Curve2 -> IO ()
foreign import ccall "blst_p1_from_affine" c_blst_p1_from_affine :: PPtr Curve1 -> AffinePtr Curve1 -> IO ()
foreign import ccall "blst_p2_from_affine" c_blst_p2_from_affine :: PPtr Curve2 -> AffinePtr Curve2 -> IO ()

foreign import ccall "blst_p1_affine_in_g1" c_blst_p1_affine_in_g1 :: AffinePtr Curve1 -> IO Bool
foreign import ccall "blst_p2_affine_in_g2" c_blst_p2_affine_in_g2 :: AffinePtr Curve2 -> IO Bool

---- Pairing check

foreign import ccall "blst_two_miller_one_exp" c_blst_two_miller_one_exp ::
  Affine1Ptr -> Affine1Ptr -> Affine2Ptr -> Affine2Ptr -> IO Bool

---- Raw BLST error constants

foreign import ccall "blst_success" c_blst_success :: CInt
foreign import ccall "blst_error_bad_encoding" c_blst_error_bad_encoding :: CInt
foreign import ccall "blst_error_point_not_on_curve" c_blst_error_point_not_on_curve :: CInt
foreign import ccall "blst_error_point_not_in_group" c_blst_error_point_not_in_group :: CInt
foreign import ccall "blst_error_aggr_type_mismatch" c_blst_error_aggr_type_mismatch :: CInt
foreign import ccall "blst_error_verify_fail" c_blst_error_verify_fail :: CInt
foreign import ccall "blst_error_pk_is_infinity" c_blst_error_pk_is_infinity :: CInt
foreign import ccall "blst_error_bad_scalar" c_blst_error_bad_scalar :: CInt

---- Utility functions

foreign import ccall "memcmp" c_memcmp :: Ptr a -> Ptr a -> CSize -> IO CSize
foreign import ccall "blst_bendian_from_fp" c_blst_bendian_from_fp :: Ptr CChar -> FPPtr -> IO ()
foreign import ccall "blst_bendian_from_scalar" c_blst_bendian_from_scalar :: Ptr CChar -> ScalarPtr -> IO ()

data BLSTError
  = BLST_SUCCESS
  | BLST_BAD_ENCODING
  | BLST_POINT_NOT_ON_CURVE
  | BLST_POINT_NOT_IN_GROUP
  | BLST_AGGR_TYPE_MISMATCH
  | BLST_VERIFY_FAIL
  | BLST_PK_IS_INFINITY
  | BLST_BAD_SCALAR
  | BLST_UNKNOWN_ERROR
  deriving (Show, Eq, Ord)

mkBLSTError :: CInt -> BLSTError
mkBLSTError e
  | e == c_blst_success
  = BLST_SUCCESS
  | e == c_blst_error_bad_encoding
  = BLST_BAD_ENCODING
  | e == c_blst_error_point_not_on_curve
  = BLST_POINT_NOT_ON_CURVE
  | e == c_blst_error_point_not_in_group
  = BLST_POINT_NOT_IN_GROUP
  | e == c_blst_error_aggr_type_mismatch
  = BLST_AGGR_TYPE_MISMATCH
  | e == c_blst_error_verify_fail
  = BLST_VERIFY_FAIL
  | e == c_blst_error_pk_is_infinity
  = BLST_PK_IS_INFINITY
  | e == c_blst_error_bad_scalar
  = BLST_BAD_SCALAR
  | otherwise
  = BLST_UNKNOWN_ERROR

class (BLS_Curve a, BLS_P a) => BLS a where

instance BLS Curve1 where

instance BLS Curve2 where

---- Curve point operations

instance BLS curve => Eq (P curve) where
  a == b = unsafePerformIO $ do
    withP a $ \aptr ->
      withP b $ \bptr ->
        c_blst_p_is_equal aptr bptr

instance Eq Scalar where
  a == b = scalarToBS a == scalarToBS b

instance Eq Fr where
  a == b = scalarFromFr a == scalarFromFr b

onCurve :: BLS_Curve curve => P curve -> Bool
onCurve p = unsafePerformIO $ withP p c_blst_on_curve

add :: (BLS_P curve, BLS_Curve curve) => P curve -> P curve -> P curve
add in1 in2 = unsafePerformIO $ do
  withNewP' $ \outp -> do
    withP in1 $ \in1p -> do
      withP in2 $ \in2p -> do
        c_blst_add outp in1p in2p

mult :: (BLS_P curve, BLS_Curve curve) => P curve -> Scalar -> P curve
mult in1 inS = unsafePerformIO $ do
  withNewP' $ \outp -> do
    withP in1 $ \in1p -> do
      withScalar inS $ \inSp -> do
        -- Multiply by 8, because blst_mult takes number of *bits*, but
        -- sizeScalar is in *bytes*
        c_blst_mult outp in1p inSp (sizeScalar * 8)

cneg :: (BLS_P curve, BLS_Curve curve) => P curve -> Bool -> P curve
cneg in1 cond = unsafePerformIO $ do
  out1 <- cloneP in1
  withP out1 $ \out1p ->
    c_blst_cneg out1p cond
  return out1

neg :: (BLS_P curve, BLS_Curve curve) => P curve -> P curve
neg p = cneg p True

uncompress :: forall curve. (BLS_P curve, BLS_Curve curve) => ByteString -> Either BLSTError (P curve)
uncompress bs = unsafePerformIO $ do
  BS.useAsCStringLen bs $ \(bytes, numBytes) -> do
    if numBytes < compressedSizeP (Proxy @curve) then
      return $ Left BLST_BAD_ENCODING
    else do
      (err, affine) <- withNewAffine $ \ap -> c_blst_uncompress ap bytes
      if err /= 0 then
        return $ Left $ mkBLSTError err
      else
        return $ Right (fromAffine affine)

deserialize :: forall curve. (BLS_P curve, BLS_Curve curve) => ByteString -> Either BLSTError (P curve)
deserialize bs = unsafePerformIO $ do
  BS.useAsCStringLen bs $ \(bytes, numBytes) -> do
    if numBytes < serializedSizeP (Proxy @curve) then
      return $ Left BLST_BAD_ENCODING
    else do
      (err, affine) <- withNewAffine $ \ap -> c_blst_deserialize ap bytes
      if err /= 0 then
        return $ Left $ mkBLSTError err
      else
        return $ Right (fromAffine affine)

compress :: forall curve. (BLS_P curve, BLS_Curve curve) => P curve -> ByteString
compress p = unsafePerformIO $ do
  withP p $ \pp -> do
    cstr <- mallocForeignPtrBytes (compressedSizeP (Proxy @curve))
    withForeignPtr cstr $ \cstrp -> do
      c_blst_compress cstrp pp
      BS.packCStringLen (cstrp, compressedSizeP (Proxy @curve))

serialize :: forall curve. (BLS_P curve, BLS_Curve curve) => P curve -> ByteString
serialize p = unsafePerformIO $ do
  withP p $ \pp -> do
    cstr <- mallocForeignPtrBytes (serializedSizeP (Proxy @curve))
    withForeignPtr cstr $ \cstrp -> do
      c_blst_serialize cstrp pp
      BS.packCStringLen (cstrp, serializedSizeP (Proxy @curve))

hash :: (BLS_P curve, BLS_Curve curve) => ByteString -> Maybe ByteString -> Maybe ByteString -> P curve
hash msg mDST mAug = unsafePerformIO $
  BS.useAsCStringLen msg $ \(msgPtr, msgLen) ->
    withMaybeCStringLen mDST $ \(dstPtr, dstLen) ->
      withMaybeCStringLen mAug $ \(augPtr, augLen) ->
        withNewP' $ \pPtr ->
          c_blst_hash pPtr msgPtr (fromIntegral msgLen) dstPtr (fromIntegral dstLen) augPtr (fromIntegral augLen)

toAffine :: (BLS_P curve, BLS_Curve curve) => P curve -> Affine curve
toAffine p = unsafePerformIO $
  withP p $ \pp ->
    withNewAffine' $ \affinePtr ->
      c_blst_to_affine affinePtr pp

fromAffine :: (BLS_P curve, BLS_Curve curve) => Affine curve -> P curve
fromAffine affine = unsafePerformIO $
  withAffine affine $ \affinePtr ->
    withNewP' $ \pp ->
      c_blst_from_affine pp affinePtr

isInf :: (BLS_Curve curve) => P curve -> Bool
isInf p = unsafePerformIO $ withP p c_blst_p_is_inf

getX :: (BLS_Curve curve) => P curve -> Natural
getX p = unsafePerformIO $ fpToNat =<< do
  withNewFP' $ \fPtr -> do
    withP p $ \pPtr -> do
      c_blst_x_from_p fPtr pPtr
getY :: (BLS_Curve curve) => P curve -> Natural
getY p = unsafePerformIO $ fpToNat =<< do
  withNewFP' $ \fPtr -> do
    withP p $ \pPtr -> do
      c_blst_y_from_p fPtr pPtr
getZ :: (BLS_Curve curve) => P curve -> Natural
getZ p = unsafePerformIO $ fpToNat =<< do
  withNewFP' $ \fPtr -> do
    withP p $ \pPtr -> do
      c_blst_z_from_p fPtr pPtr

getAX :: (BLS_Curve curve) => Affine curve -> Natural
getAX aff = unsafePerformIO $ fpToNat =<< do
  withNewFP' $ \fPtr -> do
    withAffine aff $ \affPtr -> do
      c_blst_x_from_affine fPtr affPtr
getAY :: (BLS_Curve curve) => Affine curve -> Natural
getAY aff = unsafePerformIO $ fpToNat =<< do
  withNewFP' $ \fPtr -> do
    withAffine aff $ \affPtr -> do
      c_blst_y_from_affine fPtr affPtr

toXYZ :: (BLS_Curve curve) => P curve -> (Natural, Natural, Natural)
toXYZ p = (getX p, getY p, getZ p)

toXY :: (BLS_Curve curve) => Affine curve -> (Natural, Natural)
toXY aff = (getAX aff, getAY aff)

affineInG :: (BLS_Curve curve) => Affine curve -> Bool
affineInG affine = unsafePerformIO $
  withAffine affine c_blst_affine_in_g

generator :: (BLS_Curve curve) => P curve
generator = unsafePFromPPtr c_blst_generator

---- Scalar / Fr operations

scalarFromFr :: Fr -> Scalar
scalarFromFr fr = unsafePerformIO $
  withNewScalar' $ \scalarPtr ->
    withFr fr $ \frPtr ->
      c_blst_scalar_from_fr scalarPtr frPtr

frFromScalar :: Scalar -> Fr
frFromScalar scalar =
  unsafePerformIO $
    withNewFr' $ \frPtr ->
      withScalar scalar $ \scalarPtr ->
        c_blst_fr_from_scalar frPtr scalarPtr

frFromCanonicalScalar :: Scalar -> Maybe Fr
frFromCanonicalScalar scalar
  | scalarCanonical scalar
  = Just $ frFromScalar scalar
  | otherwise
  = Nothing

scalarFromBS :: ByteString -> Either BLSTError Scalar
scalarFromBS bs =
  if success then
    Right scalar
  else
    Left BLST_BAD_SCALAR
  where
    (success, scalar) = unsafePerformIO $
      withNewScalar $ \scalarPtr ->
        BS.useAsCStringLen bs $ \(cstr, l) ->
          c_blst_scalar_from_be_bytes scalarPtr cstr (fromIntegral l)

scalarToBS :: Scalar -> ByteString
scalarToBS scalar = unsafePerformIO $ do
  cstr <- mallocForeignPtrBytes sizeScalar
  withForeignPtr cstr $ \cstrp -> do
    withScalar scalar $ \scalarPtr -> do
      c_blst_bendian_from_scalar cstrp scalarPtr
      BS.packCStringLen (castPtr cstrp, sizeScalar)

frAdd :: Fr -> Fr -> Fr
frAdd a b = unsafePerformIO $
  withNewFr' $ \outPtr ->
    withFr a $ \aPtr ->
      withFr b $ \bPtr ->
        c_blst_fr_add outPtr aPtr bPtr

frMult :: Fr -> Fr -> Fr
frMult a b = unsafePerformIO $
  withNewFr' $ \outPtr ->
    withFr a $ \aPtr ->
      withFr b $ \bPtr ->
        c_blst_fr_mul outPtr aPtr bPtr

frNeg :: Fr -> Fr
frNeg a = unsafePerformIO $
  withNewFr' $ \outPtr ->
    withFr a $ \aPtr ->
      c_blst_fr_cneg outPtr aPtr

frInverse :: Fr -> Fr
frInverse a = unsafePerformIO $
  withNewFr' $ \outPtr ->
    withFr a $ \aPtr ->
      c_blst_fr_inverse outPtr aPtr

frSqr :: Fr -> Fr
frSqr a = unsafePerformIO $
  withNewFr' $ \outPtr ->
    withFr a $ \aPtr ->
      c_blst_fr_sqr outPtr aPtr

scalarCanonical :: Scalar -> Bool
scalarCanonical scalar = unsafePerformIO $
  withScalar scalar c_blst_scalar_fr_check

scalarToNatural :: Scalar -> Natural
scalarToNatural = unsafePerformIO . scalarToNat

scalarFromNatural :: Natural -> Scalar
scalarFromNatural = unsafePerformIO . scalarFromNat

frFromNatural :: Natural -> Fr
frFromNatural = frFromScalar . scalarFromNatural

frToNatural :: Fr -> Natural
frToNatural = scalarToNatural . scalarFromFr

---- Pairings

pairingCheck :: (P1, P2) -> (P1, P2) -> Bool
pairingCheck (p1, p2) (q1, q2) = unsafePerformIO $ do
  withAffine a1 $ \ap1 ->
    withAffine a2 $ \ap2 ->
      withAffine b1 $ \bp1 ->
        withAffine b2 $ \bp2 ->
          c_blst_two_miller_one_exp ap1 bp1 ap2 bp2
  where
    a1 = toAffine (neg p1)
    a2 = toAffine p2
    b1 = toAffine q1
    b2 = toAffine q2



---- Utility

withMaybeCStringLen :: Maybe ByteString -> (CStringLen -> IO a) -> IO a
withMaybeCStringLen Nothing go = go (nullPtr, 0)
withMaybeCStringLen (Just bs) go = BS.useAsCStringLen bs go
