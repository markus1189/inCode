{-# LANGUAGE DeriveGeneric #-}
-- http://blog.jle.im/entry/streaming-huffman-compression-in-haskell-part-1-trees
-- http://blog.jle.im/entry/streaming-huffman-compression-in-haskell-part-2-binary

module PreTree where

import Control.Applicative       ((<$>),(<*>),(<|>))
import Data.Binary
import Data.List                 (unfoldr)
import Data.Map.Strict           (Map)
import Data.Monoid               ((<>))
import GHC.Generics
import Weighted
import qualified Data.Map.Strict as M

-- | Types
--
-- PrefixTree: The data type used to implement a huffman encoding tree.
data PreTree a = PTLeaf a
               | PTNode (PreTree a) (PreTree a)
               deriving (Show, Eq, Generic)

-- Direction: Indicates a left or right direction of going down the tree.
--      Used to encode input.
data Direction = DLeft
               | DRight
               deriving (Show, Eq, Generic)

-- Encoding: A type signature for a list of `Direction`s.
type Encoding = [Direction]

instance Binary Direction

-- Binary instance for `PreTree a`; allows it to be serialized and
--      deserialized.
instance Binary a => Binary (PreTree a) where
    put = putPT
    get = getPT

-- Alternatively, to generate a Binary instance automatically:
-- instance Binary a => Binary (PreTree a)

-- | PreTree
--
-- makePT: Wraps something in a new singleton PreTree.
makePT :: a -> PreTree a
makePT = PTLeaf

-- mergePT: Merges two PreTree's together into one big one.
mergePT :: PreTree a -> PreTree a -> PreTree a
mergePT = PTNode

-- WeightedPT: Type synonym for a PreTree with an attached weight.
type WeightedPT a = Weighted (PreTree a)

-- makeWPT: Wraps something in a new singleton PreTree, with an associated
--      weight.
makeWPT :: Int -> a -> WeightedPT a
makeWPT w = WPair w . makePT

-- mergeWPT: Merges two weighted PreTrees, adding together their weights.
mergeWPT :: WeightedPT a -> WeightedPT a -> WeightedPT a
mergeWPT (WPair w1 pt1) (WPair w2 pt2)
    = WPair (w1 + w2) (mergePT pt1 pt2)

-- | Serialization/deserialization
--
-- putPT: Describes how to serialize a PreTree
putPT :: Binary a => PreTree a -> Put
putPT (PTLeaf x) = do
    put True                    -- signify we have a leaf
    put x
putPT (PTNode pt1 pt2) = do
    put False                   -- signify we have a node
    put pt1
    put pt2

-- getPT: Describes how to unserialize a PreTree
getPT :: Binary a => Get (PreTree a)
getPT = do
    isLeaf <- get
    if isLeaf
      then PTLeaf <$> get
      else PTNode <$> get <*> get

-- | Encoding
--
-- findPT: A naive depth-first search which returns the encoding of the
--      first match it finds.
findPT :: Eq a => PreTree a -> a -> Maybe Encoding
findPT pt0 x = go pt0 []
  where
    go (PTLeaf y      ) enc | x == y    = Just (reverse enc)
                            | otherwise = Nothing
    go (PTNode pt1 pt2) enc = go pt1 (DLeft  : enc) <|>
                              go pt2 (DRight : enc)

-- ptTable: Builds a table of inputs and their encodings, by replacing
--      every node with a singleton Map using a depth first traversal, then
--      combining all of them with `(<>)` (mappend).
ptTable :: Ord a => PreTree a -> Map a Encoding
ptTable pt = go pt []
  where
    go (PTLeaf x) enc       = x `M.singleton` reverse enc
    go (PTNode pt1 pt2) enc = go pt1 (DLeft  : enc) <>
                              go pt2 (DRight : enc)

-- lookupPTTable: Looks up the given input in the given memoization table
--      (generated by `ptTable`).
lookupPTTable :: Ord a => Map a Encoding -> a -> Maybe Encoding
lookupPTTable = flip M.lookup

-- encodeAll: Encodes an entire input sequence using the given prefix tree.
encodeAll :: Ord a => PreTree a -> [a] -> Maybe Encoding
encodeAll pt xs = concat <$> sequence (map (lookupPTTable tb) xs)
  where
    tb = ptTable pt

-- decodePT: Finds the first decoded output inside an encoded string,
--      using the given PreTree.  Returns a possibly successful result as
--      well as the leftover encoded string.  Fails if the string runs out
--      too soon.
decodePT :: PreTree a -> Encoding -> Maybe (a, Encoding)
decodePT (PTLeaf x)       ds     = Just (x, ds)
decodePT (PTNode pt1 pt2) (d:ds) = case d of
                                     DLeft  -> decodePT pt1 ds
                                     DRight -> decodePT pt2 ds
decodePT (PTNode _ _)     []     = Nothing

-- decodeAll: Repeatedly eats the encoded string until it runs out.  Will
--      not terminate if the PreTree is singleton.
decodeAll :: PreTree a -> Encoding -> [a]
decodeAll pt = unfoldr (decodePT pt)

-- decodeAll: Repeatedly eats the encoded string until it runs out.  Will
--      return `Nothing` if the PreTree is singleton.
decodeAll' :: PreTree a -> Encoding -> Maybe [a]
decodeAll' (PTLeaf _) _   = Nothing
decodeAll' pt         enc = Just $ unfoldr (decodePT pt) enc
