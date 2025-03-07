{-# LANGUAGE CPP                     #-}
{-# LANGUAGE ConstrainedClassMethods #-}
{-# LANGUAGE ConstraintKinds         #-}
{-# LANGUAGE DataKinds               #-}
{-# LANGUAGE DefaultSignatures       #-}
{-# LANGUAGE FlexibleContexts        #-}
{-# LANGUAGE FlexibleInstances       #-}
{-# LANGUAGE Trustworthy             #-}
{-# LANGUAGE TypeFamilies            #-}
{-# LANGUAGE TypeOperators           #-}
{-# LANGUAGE UndecidableInstances    #-}

{-# OPTIONS_GHC -fno-warn-unticked-promoted-constructors #-}
{-# OPTIONS_GHC -Wno-unused-type-patterns #-}

-- | Reimagined approach for 'Foldable' type hierarchy. Forbids usages
-- of 'length' function and similar over 'Maybe' and other potentially unsafe
-- data types. It was proposed to use @-XTypeApplication@ for such cases.
-- But this approach is not robust enough because programmers are human and can
-- easily forget to do this. For discussion see this topic:
-- <https://www.reddit.com/r/haskell/comments/60r9hu/proposal_suggest_explicit_type_application_for/ Suggest explicit type application for Foldable length and friends>

module Universum.Container.Class
       ( -- * Foldable-like classes and methods
         ToPairs   (..)
       , FromList  (..)
       , Container (..)
       , checkingNotNull

       , flipfoldl'

       , sum
       , product

       , mapM_
       , forM_
       , traverse_
       , for_
       , sequenceA_
       , sequence_
       , asum

         -- * Others
       , One(..)
       ) where

import Data.Coerce (Coercible, coerce)
import Data.Kind (Type)
import Prelude hiding (all, and, any, elem, foldMap, foldl, foldr, mapM_, notElem, null, or, print,
                product, sequence_, sum)

import Universum.Applicative (Alternative (..), Const, ZipList (..), pass)
import Universum.Base (HasCallStack, Word8)
import Universum.Container.Reexport (HashMap, HashSet, Hashable, IntMap, IntSet, Map, Seq, Set,
                                     Vector)
import Universum.Functor (Identity)
import Universum.Monoid (All (..), Any (..), Dual, First (..), Last, Product, Sum)

import qualified GHC.Exts as Exts
import GHC.TypeLits (ErrorMessage (..), Symbol, TypeError)

import qualified Data.List.NonEmpty as NE
import Universum.List.Reexport (NonEmpty)

import qualified Data.Foldable as Foldable

import qualified Data.Sequence as SEQ

import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as BSL

import qualified Data.Text as T
import qualified Data.Text.Lazy as TL

import qualified Data.HashMap.Strict as HM
import qualified Data.HashSet as HashSet
import qualified Data.IntMap as IM
import qualified Data.IntSet as IS
import qualified Data.Map as M
import qualified Data.Set as Set

import qualified Data.Vector as V
import qualified Data.Vector.Primitive as VP
import qualified Data.Vector.Storable as VS
import qualified Data.Vector.Unboxed as VU

-- $setup
-- >>> import Universum.Base (even)
-- >>> import Universum.Bool (when)
-- >>> import Universum.Print (print, putTextLn)
-- >>> import Universum.String (Text)
-- >>> import qualified Data.HashMap.Strict as HashMap

----------------------------------------------------------------------------
-- ToPairs
----------------------------------------------------------------------------

{- | Type class for data types that can be converted to List of Pairs.
 You can define 'ToPairs' by just defining 'toPairs' function.

 But the following laws should be met:

@
'toPairs' m ≡ 'zip' ('keys' m) ('elems' m)
'keys'      ≡ 'map' 'fst' . 'toPairs'
'elems'     ≡ 'map' 'snd' . 'toPairs'
@

-}
class ToPairs t where
    {-# MINIMAL toPairs #-}
    -- | Type of keys of the mapping.
    type Key t :: Type
    -- | Type of value of the mapping.
    type Val t :: Type

    -- | Converts the structure to the list of the key-value pairs.
    -- >>> toPairs (HashMap.fromList [('a', "xxx"), ('b', "yyy")])
    -- [('a',"xxx"),('b',"yyy")]
    toPairs :: t -> [(Key t, Val t)]

    -- | Converts the structure to the list of the keys.
    --
    -- >>> keys (HashMap.fromList [('a', "xxx"), ('b', "yyy")])
    -- "ab"
    keys :: t -> [Key t]
    keys = map fst . toPairs
    {-# INLINE keys #-}

    -- | Converts the structure to the list of the values.
    --
    -- >>> elems (HashMap.fromList [('a', "xxx"), ('b', "yyy")])
    -- ["xxx","yyy"]
    elems :: t -> [Val t]
    elems = map snd . toPairs
    {-# INLINE elems #-}

-- Instances

instance ToPairs (HashMap k v) where
    type Key (HashMap k v) = k
    type Val (HashMap k v) = v
    toPairs = HM.toList
    {-# INLINE toPairs #-}
    keys    = HM.keys
    {-# INLINE keys #-}
    elems   = HM.elems
    {-# INLINE elems #-}

instance ToPairs (IntMap v) where
    type Key (IntMap v) = Int
    type Val (IntMap v) = v
    toPairs = IM.toList
    {-# INLINE toPairs #-}
    keys    = IM.keys
    {-# INLINE keys #-}
    elems   = IM.elems
    {-# INLINE elems #-}

instance ToPairs (Map k v) where
    type Key (Map k v) = k
    type Val (Map k v) = v
    toPairs = M.toList
    {-# INLINE toPairs #-}
    keys    = M.keys
    {-# INLINE keys #-}
    elems   = M.elems
    {-# INLINE elems #-}

----------------------------------------------------------------------------
-- FromList
----------------------------------------------------------------------------

-- | Type class for data types that can be constructed from a list.
class FromList l where
  type ListElement l :: Type
  type ListElement l = Exts.Item l

  type FromListC l :: Exts.Constraint
  type FromListC l = ()

  {- | Make a value from list.

  For simple types like '[]' and 'Set':

  @
  'toList' . 'fromList' ≡ id
  'fromList' . 'toList' ≡ id
  @

  For map-like types:

  @
  'toPairs' . 'fromList' ≡ id
  'fromList' . 'toPairs' ≡ id
  @

  -}
  fromList :: FromListC l => [ListElement l] -> l
  default fromList
    :: (Exts.IsList l, Exts.Item l ~ a, ListElement l ~ a)
    => [ListElement l] -> l
  fromList = Exts.fromList

instance FromList [a]
instance FromList (Vector a)
instance FromList (Seq a)
instance FromList (ZipList a) where
    type ListElement (ZipList a) = a
    fromList = ZipList
instance FromList (NonEmpty a) where
    type FromListC (NonEmpty a) = HasCallStack
    fromList l = case l of
      []     -> error "empty list"
      x : xs -> x NE.:| xs

instance FromList IntSet
instance Ord a => FromList (Set a)
instance (Eq k, Hashable k) => FromList (HashMap k v)
instance FromList (IntMap v)
instance Ord k => FromList (Map k v)

instance FromList T.Text
instance FromList TL.Text
instance FromList BS.ByteString where
    type ListElement BS.ByteString = Word8
    fromList = BS.pack
instance FromList BSL.ByteString where
    type ListElement BSL.ByteString = Word8
    fromList = BSL.pack

----------------------------------------------------------------------------
-- Containers (e.g. tuples and Maybe aren't containers)
----------------------------------------------------------------------------

-- | Default implementation of 'Element' associated type family.
type family ElementDefault (t :: Type) :: Type where
    ElementDefault (_ a) = a

-- | Very similar to 'Foldable' but also allows instances for monomorphic types
-- like 'Text' but forbids instances for 'Maybe' and similar. This class is used as
-- a replacement for 'Foldable' type class. It solves the following problems:
--
-- 1. 'length', 'foldr' and other functions work on more types for which it makes sense.
-- 2. You can't accidentally use 'length' on polymorphic 'Foldable' (like list),
--    replace list with 'Maybe' and then debug error for two days.
-- 3. More efficient implementaions of functions for polymorphic types (like 'elem' for 'Set').
--
-- The drawbacks:
--
-- 1. Type signatures of polymorphic functions look more scary.
-- 2. Orphan instances are involved if you want to use 'foldr' (and similar) on types from libraries.
class Container t where
    -- | Type of element for some container. Implemented as an asscociated type family because
    -- some containers are monomorphic over element type (like 'T.Text', 'IntSet', etc.)
    -- so we can't implement nice interface using old higher-kinded types
    -- approach. Implementing this as an associated type family instead of
    -- top-level family gives you more control over element types.
    type Element t :: Type
    type Element t = ElementDefault t

    -- | Convert container to list of elements.
    --
    -- >>> toList @Text "aba"
    -- "aba"
    -- >>> :t toList @Text "aba"
    -- toList @Text "aba" :: [Char]
    toList :: t -> [Element t]
    default toList :: (Foldable f, t ~ f a, Element t ~ a) => t -> [Element t]
    toList = Foldable.toList
    {-# INLINE toList #-}

    -- | Checks whether container is empty.
    --
    -- >>> null @Text ""
    -- True
    -- >>> null @Text "aba"
    -- False
    null :: t -> Bool
    default null :: (Foldable f, t ~ f a) => t -> Bool
    null = Foldable.null
    {-# INLINE null #-}

    foldr :: (Element t -> b -> b) -> b -> t -> b
    default foldr :: (Foldable f, t ~ f a, Element t ~ a) => (Element t -> b -> b) -> b -> t -> b
    foldr = Foldable.foldr
    {-# INLINE foldr #-}

    foldl :: (b -> Element t -> b) -> b -> t -> b
    default foldl :: (Foldable f, t ~ f a, Element t ~ a) => (b -> Element t -> b) -> b -> t -> b
    foldl = Foldable.foldl
    {-# INLINE foldl #-}

    foldl' :: (b -> Element t -> b) -> b -> t -> b
    default foldl' :: (Foldable f, t ~ f a, Element t ~ a) => (b -> Element t -> b) -> b -> t -> b
    foldl' = Foldable.foldl'
    {-# INLINE foldl' #-}

    length :: t -> Int
    default length :: (Foldable f, t ~ f a) => t -> Int
    length = Foldable.length
    {-# INLINE length #-}

    elem :: Eq (Element t) => Element t -> t -> Bool
    default elem :: ( Foldable f
                    , t ~ f a
                    , Element t ~ a
                    , Eq a
                    ) => Element t -> t -> Bool
    elem = Foldable.elem
    {-# INLINE elem #-}

    foldMap :: Monoid m => (Element t -> m) -> t -> m
    foldMap f = foldr (mappend . f) mempty
    {-# INLINE foldMap #-}

    fold :: Monoid (Element t) => t -> Element t
    fold = foldMap id
    {-# INLINE fold #-}

    foldr' :: (Element t -> b -> b) -> b -> t -> b
    foldr' f z0 xs = foldl f' id xs z0
      where f' k x z = k $! f x z
    {-# INLINE foldr' #-}

    notElem :: Eq (Element t) => Element t -> t -> Bool
    notElem x = not . elem x
    {-# INLINE notElem #-}

    all :: (Element t -> Bool) -> t -> Bool
    all p = getAll #. foldMap (All #. p)
    any :: (Element t -> Bool) -> t -> Bool
    any p = getAny #. foldMap (Any #. p)
    {-# INLINE all #-}
    {-# INLINE any #-}

    and :: (Element t ~ Bool) => t -> Bool
    and = getAll #. foldMap All
    or :: (Element t ~ Bool) => t -> Bool
    or = getAny #. foldMap Any
    {-# INLINE and #-}
    {-# INLINE or #-}

    find :: (Element t -> Bool) -> t -> Maybe (Element t)
    find p = getFirst . foldMap (\ x -> First (if p x then Just x else Nothing))
    {-# INLINE find #-}

    safeHead :: t -> Maybe (Element t)
    safeHead = foldr (\x _ -> Just x) Nothing
    {-# INLINE safeHead #-}

    safeMaximum :: Ord (Element t) => t -> Maybe (Element t)
    default safeMaximum
      :: (Foldable f, t ~ f a, Element t ~ a, Ord (Element t))
      => t -> Maybe (Element t)
    safeMaximum = checkingNotNull Foldable.maximum
    {-# INLINE safeMaximum #-}

    safeMinimum :: Ord (Element t) => t -> Maybe (Element t)
    default safeMinimum
      :: (Foldable f, t ~ f a, Element t ~ a, Ord (Element t))
      => t -> Maybe (Element t)
    safeMinimum = checkingNotNull Foldable.minimum
    {-# INLINE safeMinimum #-}

    safeFoldr1 :: (Element t -> Element t -> Element t) -> t -> Maybe (Element t)
    safeFoldr1 f xs = foldr mf Nothing xs
      where
        mf x m = Just (case m of
                           Nothing -> x
                           Just y  -> f x y)
    {-# INLINE safeFoldr1 #-}

    safeFoldl1 :: (Element t -> Element t -> Element t) -> t -> Maybe (Element t)
    safeFoldl1 f xs = foldl mf Nothing xs
      where
        mf m y = Just (case m of
                           Nothing -> y
                           Just x  -> f x y)
    {-# INLINE safeFoldl1 #-}

-- | Helper for lifting operations which require container to be not empty.
checkingNotNull :: Container t => (t -> Element t) -> t -> Maybe (Element t)
checkingNotNull f t
  | null t = Nothing
  | otherwise = Just $ f t
{-# INLINE checkingNotNull #-}

----------------------------------------------------------------------------
-- Instances for monomorphic containers
----------------------------------------------------------------------------

instance Container T.Text where
    type Element T.Text = Char
    toList = T.unpack
    {-# INLINE toList #-}
    null = T.null
    {-# INLINE null #-}
    foldr = T.foldr
    {-# INLINE foldr #-}
    foldl = T.foldl
    {-# INLINE foldl #-}
    foldl' = T.foldl'
    {-# INLINE foldl' #-}
    safeFoldr1 f = checkingNotNull (T.foldr1 f)
    {-# INLINE safeFoldr1 #-}
    safeFoldl1 f = checkingNotNull (T.foldl1 f)
    {-# INLINE safeFoldl1 #-}
    length = T.length
    {-# INLINE length #-}
    elem c = T.isInfixOf (T.singleton c)  -- there are rewrite rules for this
    {-# INLINE elem #-}
    safeMaximum = checkingNotNull T.maximum
    {-# INLINE safeMaximum #-}
    safeMinimum = checkingNotNull T.minimum
    {-# INLINE safeMinimum #-}
    all = T.all
    {-# INLINE all #-}
    any = T.any
    {-# INLINE any #-}
    find = T.find
    {-# INLINE find #-}
    safeHead = fmap fst . T.uncons
    {-# INLINE safeHead #-}

instance Container TL.Text where
    type Element TL.Text = Char
    toList = TL.unpack
    {-# INLINE toList #-}
    null = TL.null
    {-# INLINE null #-}
    foldr = TL.foldr
    {-# INLINE foldr #-}
    foldl = TL.foldl
    {-# INLINE foldl #-}
    foldl' = TL.foldl'
    {-# INLINE foldl' #-}
    safeFoldr1 f = checkingNotNull (TL.foldr1 f)
    {-# INLINE safeFoldr1 #-}
    safeFoldl1 f = checkingNotNull (TL.foldl1 f)
    {-# INLINE safeFoldl1 #-}
    length = fromIntegral . TL.length
    {-# INLINE length #-}
    -- will be okay thanks to rewrite rules
    elem c s = TL.isInfixOf (TL.singleton c) s
    {-# INLINE elem #-}
    safeMaximum = checkingNotNull TL.maximum
    {-# INLINE safeMaximum #-}
    safeMinimum = checkingNotNull TL.minimum
    {-# INLINE safeMinimum #-}
    all = TL.all
    {-# INLINE all #-}
    any = TL.any
    {-# INLINE any #-}
    find = TL.find
    {-# INLINE find #-}
    safeHead = fmap fst . TL.uncons
    {-# INLINE safeHead #-}

instance Container BS.ByteString where
    type Element BS.ByteString = Word8
    toList = BS.unpack
    {-# INLINE toList #-}
    null = BS.null
    {-# INLINE null #-}
    foldr = BS.foldr
    {-# INLINE foldr #-}
    foldl = BS.foldl
    {-# INLINE foldl #-}
    foldl' = BS.foldl'
    {-# INLINE foldl' #-}
    safeFoldr1 f = checkingNotNull (BS.foldr1 f)
    {-# INLINE safeFoldr1 #-}
    safeFoldl1 f = checkingNotNull (BS.foldl1 f)
    {-# INLINE safeFoldl1 #-}
    length = BS.length
    {-# INLINE length #-}
    elem = BS.elem
    {-# INLINE elem #-}
    notElem = BS.notElem
    {-# INLINE notElem #-}
    safeMaximum = checkingNotNull BS.maximum
    {-# INLINE safeMaximum #-}
    safeMinimum = checkingNotNull BS.minimum
    {-# INLINE safeMinimum #-}
    all = BS.all
    {-# INLINE all #-}
    any = BS.any
    {-# INLINE any #-}
    find = BS.find
    {-# INLINE find #-}
    safeHead = fmap fst . BS.uncons
    {-# INLINE safeHead #-}

instance Container BSL.ByteString where
    type Element BSL.ByteString = Word8
    toList = BSL.unpack
    {-# INLINE toList #-}
    null = BSL.null
    {-# INLINE null #-}
    foldr = BSL.foldr
    {-# INLINE foldr #-}
    foldl = BSL.foldl
    {-# INLINE foldl #-}
    foldl' = BSL.foldl'
    {-# INLINE foldl' #-}
    safeFoldr1 f = checkingNotNull (BSL.foldr1 f)
    {-# INLINE safeFoldr1 #-}
    safeFoldl1 f = checkingNotNull (BSL.foldl1 f)
    {-# INLINE safeFoldl1 #-}
    length = fromIntegral . BSL.length
    {-# INLINE length #-}
    elem = BSL.elem
    {-# INLINE elem #-}
    notElem = BSL.notElem
    {-# INLINE notElem #-}
    safeMaximum = checkingNotNull BSL.maximum
    {-# INLINE safeMaximum #-}
    safeMinimum = checkingNotNull BSL.minimum
    {-# INLINE safeMinimum #-}
    all = BSL.all
    {-# INLINE all #-}
    any = BSL.any
    {-# INLINE any #-}
    find = BSL.find
    {-# INLINE find #-}
    safeHead = fmap fst . BSL.uncons
    {-# INLINE safeHead #-}

instance Container IntSet where
    type Element IntSet = Int
    toList = IS.toList
    {-# INLINE toList #-}
    null = IS.null
    {-# INLINE null #-}
    foldr = IS.foldr
    {-# INLINE foldr #-}
    foldl = IS.foldl
    {-# INLINE foldl #-}
    foldl' = IS.foldl'
    {-# INLINE foldl' #-}
    length = IS.size
    {-# INLINE length #-}
    elem = IS.member
    {-# INLINE elem #-}
    safeMaximum = checkingNotNull IS.findMax
    {-# INLINE safeMaximum #-}
    safeMinimum = checkingNotNull IS.findMin
    {-# INLINE safeMinimum #-}
    safeHead = fmap fst . IS.minView
    {-# INLINE safeHead #-}

----------------------------------------------------------------------------
-- Efficient instances
----------------------------------------------------------------------------

instance Ord v => Container (Set v) where
    elem = Set.member
    {-# INLINE elem #-}
    notElem = Set.notMember
    {-# INLINE notElem #-}

instance (Eq v, Hashable v) => Container (HashSet v) where
    elem = HashSet.member
    {-# INLINE elem #-}

----------------------------------------------------------------------------
-- Boilerplate instances (duplicate Foldable)
----------------------------------------------------------------------------

-- Basic types
instance Container [a]
instance Container (Const a b)

-- Algebraic types
instance Container (Dual a)
instance Container (First a)
instance Container (Last a)
instance Container (Product a)
instance Container (Sum a)
instance Container (NonEmpty a)
instance Container (ZipList a)

-- Containers
instance Container (HashMap k v)
instance Container (IntMap v)
instance Container (Map k v)
instance Container (Seq a)
instance Container (Vector a)

----------------------------------------------------------------------------
-- Derivative functions
----------------------------------------------------------------------------

-- TODO: I should put different strings for different versions but I'm too lazy to do it...

{- | Similar to 'foldl'' but takes a function with its arguments flipped.

>>> flipfoldl' (/) 5 [2,3] :: Rational
15 % 2

-}
flipfoldl' :: (Container t, Element t ~ a) => (a -> b -> b) -> b -> t -> b
flipfoldl' f = foldl' (flip f)
{-# INLINE flipfoldl' #-}

-- | Stricter version of 'Prelude.sum'.
--
-- >>> sum [1..10]
-- 55
-- >>> sum (Just 3)
-- ...
--     • Do not use 'Foldable' methods on Maybe
--       Suggestions:
--           Instead of
--               for_ :: (Foldable t, Applicative f) => t a -> (a -> f b) -> f ()
--           use
--               whenJust  :: Applicative f => Maybe a    -> (a -> f ()) -> f ()
--               whenRight :: Applicative f => Either l r -> (r -> f ()) -> f ()
-- ...
--           Instead of
--               fold :: (Foldable t, Monoid m) => t m -> m
--           use
--               maybeToMonoid :: Monoid m => Maybe m -> m
-- ...
sum :: (Container t, Num (Element t)) => t -> Element t
sum = foldl' (+) 0

-- | Stricter version of 'Prelude.product'.
--
-- >>> product [1..10]
-- 3628800
-- >>> product (Right 3)
-- ...
--     • Do not use 'Foldable' methods on Either
--       Suggestions:
--           Instead of
--               for_ :: (Foldable t, Applicative f) => t a -> (a -> f b) -> f ()
--           use
--               whenJust  :: Applicative f => Maybe a    -> (a -> f ()) -> f ()
--               whenRight :: Applicative f => Either l r -> (r -> f ()) -> f ()
-- ...
--           Instead of
--               fold :: (Foldable t, Monoid m) => t m -> m
--           use
--               maybeToMonoid :: Monoid m => Maybe m -> m
-- ...
product :: (Container t, Num (Element t)) => t -> Element t
product = foldl' (*) 1

{- | Constrained to 'Container' version of 'Data.Foldable.traverse_'.

>>> traverse_ putTextLn ["foo", "bar"]
foo
bar

-}
traverse_
    :: (Container t, Applicative f)
    => (Element t -> f b) -> t -> f ()
traverse_ f = foldr ((*>) . f) pass

{- | Constrained to 'Container' version of 'Data.Foldable.for_'.

>>> for_ [1 .. 5 :: Int] $ \i -> when (even i) (print i)
2
4

-}
for_
    :: (Container t, Applicative f)
    => t -> (Element t -> f b) -> f ()
for_ = flip traverse_
{-# INLINE for_ #-}

{- | Constrained to 'Container' version of 'Data.Foldable.mapM_'.

>>> mapM_ print [True, False]
True
False

-}
mapM_
    :: (Container t, Monad m)
    => (Element t -> m b) -> t -> m ()
mapM_ f= foldr ((>>) . f) pass

{- | Constrained to 'Container' version of 'Data.Foldable.forM_'.

>>> forM_ [True, False] print
True
False

-}
forM_
    :: (Container t, Monad m)
    => t -> (Element t -> m b) -> m ()
forM_ = flip mapM_
{-# INLINE forM_ #-}

{- | Constrained to 'Container' version of 'Data.Foldable.sequenceA_'.

>>> sequenceA_ [putTextLn "foo", print True]
foo
True

-}
sequenceA_
    :: (Container t, Applicative f, Element t ~ f a)
    => t -> f ()
sequenceA_ = foldr (*>) pass

{- | Constrained to 'Container' version of 'Data.Foldable.sequence_'.

>>> sequence_ [putTextLn "foo", print True]
foo
True

-}
sequence_
    :: (Container t, Monad m, Element t ~ m a)
    => t -> m ()
sequence_ = foldr (>>) pass

{- | Constrained to 'Container' version of 'Data.Foldable.asum'.

>>> asum [Nothing, Just [False, True], Nothing, Just [True]]
Just [False,True]

-}
asum
    :: (Container t, Alternative f, Element t ~ f a)
    => t -> f a
asum = foldr (<|>) empty
{-# INLINE asum #-}

----------------------------------------------------------------------------
-- Disallowed instances
----------------------------------------------------------------------------

type family DisallowInstance (z :: Symbol) :: ErrorMessage where
    DisallowInstance z  = Text "Do not use 'Foldable' methods on " :<>: Text z
        :$$: Text "Suggestions:"
        :$$: Text "    Instead of"
        :$$: Text "        for_ :: (Foldable t, Applicative f) => t a -> (a -> f b) -> f ()"
        :$$: Text "    use"
        :$$: Text "        whenJust  :: Applicative f => Maybe a    -> (a -> f ()) -> f ()"
        :$$: Text "        whenRight :: Applicative f => Either l r -> (r -> f ()) -> f ()"
        :$$: Text ""
        :$$: Text "    Instead of"
        :$$: Text "        fold :: (Foldable t, Monoid m) => t m -> m"
        :$$: Text "    use"
        :$$: Text "        maybeToMonoid :: Monoid m => Maybe m -> m"
        :$$: Text ""

instance TypeError (DisallowInstance "tuple")    => Container (a, b)
instance TypeError (DisallowInstance "Maybe")    => Container (Maybe a)
instance TypeError (DisallowInstance "Either")   => Container (Either a b)
instance TypeError (DisallowInstance "Identity") => Container (Identity a)

----------------------------------------------------------------------------
-- One
----------------------------------------------------------------------------

-- | Type class for types that can be created from one element. @singleton@
-- is lone name for this function. Also constructions of different type differ:
-- @:[]@ for lists, two arguments for Maps. Also some data types are monomorphic.
--
-- >>> one True :: [Bool]
-- [True]
-- >>> one 'a' :: Text
-- "a"
-- >>> one (3, "hello") :: HashMap Int String
-- fromList [(3,"hello")]
class One x where
    type OneItem x
    -- | Create a list, map, 'Text', etc from a single element.
    one :: OneItem x -> x

-- Lists

instance One [a] where
    type OneItem [a] = a
    one = (:[])
    {-# INLINE one #-}

instance One (NE.NonEmpty a) where
    type OneItem (NE.NonEmpty a) = a
    one = (NE.:|[])
    {-# INLINE one #-}

instance One (SEQ.Seq a) where
    type OneItem (SEQ.Seq a) = a
    one = (SEQ.empty SEQ.|>)
    {-# INLINE one #-}

-- Monomorphic sequences

instance One T.Text where
    type OneItem T.Text = Char
    one = T.singleton
    {-# INLINE one #-}

instance One TL.Text where
    type OneItem TL.Text = Char
    one = TL.singleton
    {-# INLINE one #-}

instance One BS.ByteString where
    type OneItem BS.ByteString = Word8
    one = BS.singleton
    {-# INLINE one #-}

instance One BSL.ByteString where
    type OneItem BSL.ByteString = Word8
    one = BSL.singleton
    {-# INLINE one #-}

-- Maps

instance One (M.Map k v) where
    type OneItem (M.Map k v) = (k, v)
    one = uncurry M.singleton
    {-# INLINE one #-}

instance Hashable k => One (HM.HashMap k v) where
    type OneItem (HM.HashMap k v) = (k, v)
    one = uncurry HM.singleton
    {-# INLINE one #-}

instance One (IM.IntMap v) where
    type OneItem (IM.IntMap v) = (Int, v)
    one = uncurry IM.singleton
    {-# INLINE one #-}

-- Sets

instance One (Set v) where
    type OneItem (Set v) = v
    one = Set.singleton
    {-# INLINE one #-}

instance Hashable v => One (HashSet v) where
    type OneItem (HashSet v) = v
    one = HashSet.singleton
    {-# INLINE one #-}

instance One IntSet where
    type OneItem IntSet = Int
    one = IS.singleton
    {-# INLINE one #-}

-- Vectors

instance One (Vector a) where
    type OneItem (Vector a) = a
    one = V.singleton
    {-# INLINE one #-}

instance VU.Unbox a => One (VU.Vector a) where
    type OneItem (VU.Vector a) = a
    one = VU.singleton
    {-# INLINE one #-}

instance VP.Prim a => One (VP.Vector a) where
    type OneItem (VP.Vector a) = a
    one = VP.singleton
    {-# INLINE one #-}

instance VS.Storable a => One (VS.Vector a) where
    type OneItem (VS.Vector a) = a
    one = VS.singleton
    {-# INLINE one #-}

----------------------------------------------------------------------------
-- Utils
----------------------------------------------------------------------------

(#.) :: Coercible b c => (b -> c) -> (a -> b) -> (a -> c)
(#.) _f = coerce
{-# INLINE (#.) #-}
