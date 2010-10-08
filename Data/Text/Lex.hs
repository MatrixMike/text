{-# LANGUAGE OverloadedStrings #-}

-- |
-- Module      : Data.Text.Lex
-- Copyright   : (c) 2010 Bryan O'Sullivan
--
-- License     : BSD-style
-- Maintainer  : bos@serpentine.com, rtomharper@googlemail.com,
--               duncan@haskell.org
-- Stability   : experimental
-- Portability : GHC
--
-- Lexing functions used frequently when handling textual data.
module Data.Text.Lex
    (
      Lexer
    , decimal
    , hexadecimal
    , signed
    , rational
    ) where

import Control.Monad (liftM)
import Data.Char (digitToInt, isDigit, isHexDigit, ord)
import Data.Ratio
import Data.Text as T

-- | Read some text, and if the read succeeds, return its value and
-- the remaining text.
type Lexer a = Text -> Either String (a,Text)

-- | Read a decimal number.
decimal :: Integral a => Lexer a
{-# SPECIALIZE decimal :: Lexer Int #-}
decimal txt
    | T.null h  = Left "no digits in input"
    | otherwise = Right (T.foldl' go 0 h, t)
  where (h,t)  = T.spanBy isDigit txt
        go n d = (n * 10 + fromIntegral (digitToInt d))

-- | Read a hexadecimal number, with optional leading @\"0x\"@.  This
-- function is case insensitive.
hexadecimal :: Integral a => Lexer a
{-# SPECIALIZE hex :: Lexer Int #-}
hexadecimal txt
    | T.toLower h == "0x" = hex t
    | otherwise           = hex txt
 where (h,t) = T.splitAt 2 txt

hex :: Integral a => Lexer a
{-# SPECIALIZE hex :: Lexer Int #-}
hex txt
    | T.null h  = Left "no digits in input"
    | otherwise = Right (T.foldl' go 0 h, t)
  where (h,t)  = T.spanBy isHexDigit txt
        go n d = (n * 16 + fromIntegral (hexDigitToInt d))

hexDigitToInt :: Char -> Int
hexDigitToInt c
    | c >= '0' && c <= '9' = ord c - ord '0'
    | c >= 'a' && c <= 'f' = ord c - (ord 'a' - 10)
    | c >= 'A' && c <= 'F' = ord c - (ord 'A' - 10)
    | otherwise            = error "Data.Text.Lex.hexDigitToInt: bad input"

-- | Read a leading sign character (@\'-\'@ or @\'+\'@) and apply it
-- to the result of applying the given reader.
signed :: Num a => Lexer a -> Lexer a
{-# INLINE signed #-}
signed f = runP (signa (P f))

signa :: Num a => Parser a -> Parser a
{-# SPECIALIZE signa :: Parser Int -> Parser Int  #-}
signa p = do
  sign <- perhaps '+' $ char (`elem` "-+")
  if sign == '+' then p else negate `liftM` p

newtype Parser a = P {
      runP :: Text -> Either String (a,Text)
    }

instance Monad Parser where
    return a = P $ \t -> Right (a,t)
    {-# INLINE return #-}
    m >>= k  = P $ \t -> case runP m t of
                           Left err     -> Left err
                           Right (a,t') -> runP (k a) t'
    {-# INLINE (>>=) #-}
    fail msg = P $ \_ -> Left msg

perhaps :: a -> Parser a -> Parser a
perhaps def m = P $ \t -> case runP m t of
                            Left _      -> Right (def,t)
                            r@(Right _) -> r

char :: (Char -> Bool) -> Parser Char
char p = P $ \t -> case T.uncons t of
                     Just (c,t') | p c -> Right (c,t')
                     _                 -> Left "char"

-- | Read a rational number.
rational :: RealFloat a => Lexer a
{-# SPECIALIZE rational :: Lexer Double #-}
rational = runP $ do
  real <- signa (P decimal)
  (fraction,fracDigits) <- perhaps (0,0) $ do
    _ <- char (=='.')
    digits <- P $ \t -> Right (T.length $ T.takeWhile isDigit t, t)
    n <- P decimal
    return (n, digits)
  power <- perhaps 0 (char (`elem` "eE") >> signa (P decimal) :: Parser Int)
  return $! fromRational ((real % 1 + fraction % (10 ^ fracDigits)) *
                          (10 ^ power))

