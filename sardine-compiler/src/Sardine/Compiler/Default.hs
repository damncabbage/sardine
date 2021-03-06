{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TupleSections #-}
module Sardine.Compiler.Default (
    defaultOfDefinition
  , defaultOfFieldType
  ) where

import           Control.Lens ((^.))

import           Language.Haskell.Exts.QQ (hs)
import           Language.Haskell.Exts.Syntax

import           Language.Thrift.AST (Definition(..))
import           Language.Thrift.AST (Type(..), TypeReference(..))
import           Language.Thrift.AST (Enum, Union, Struct)
import           Language.Thrift.AST (HasFields(..))
import           Language.Thrift.AST (Field, FieldRequiredness(..))
import           Language.Thrift.AST (values, valueType)
import qualified Language.Thrift.AST as Thrift

import           P hiding (Enum, exp)

import           Sardine.Compiler.Data
import           Sardine.Compiler.Error
import           Sardine.Compiler.Monad
import           Sardine.Compiler.Names
import           Sardine.Compiler.Util
import           Sardine.Haskell.Combinators


defaultOfTypeReference :: TypeReference a -> Compiler a Exp
defaultOfTypeReference = \case
  DefinedType ty _ -> do
    pure $ defaultE ty
  StringType _ _ -> do
    pure [hs| T.empty |]
  BinaryType _ _ ->
    pure [hs| B.empty |]
  SListType _ annot ->
    hoistCE (SListDeprecated annot)
  BoolType _ _ ->
    pure [hs| False |]
  ByteType _ _ ->
    pure [hs| 0 |]
  I16Type _ _ ->
    pure [hs| 0 |]
  I32Type _ _ ->
    pure [hs| 0 |]
  I64Type _ _ ->
    pure [hs| 0 |]
  DoubleType _ _ ->
    pure [hs| 0 |]
  MapType _ _ _ _ -> do
    pure [hs| Hybrid.empty |]
  SetType ty _ _ -> do
    emptyVectorOfTypeReference ty
  ListType ty _ _ -> do
    emptyVectorOfTypeReference ty

defaultOfFieldType :: Field a -> Compiler a Exp
defaultOfFieldType field =
  defaultOfTypeReference (field ^. valueType)

defaultOfField :: Field a -> Compiler a Exp
defaultOfField field =
  case requiredness' field of
    Required ->
      defaultOfFieldType field
    Optional ->
      pure [hs| Nothing |]

defaultOfStruct :: Struct a -> Compiler a [Decl]
defaultOfStruct struct = do
  let
    funName = nameOfStructDefault struct
    funT = typeOfStruct struct
  fdefs <- traverse defaultOfField (struct ^. fields)
  pure . inlineFunDT funT funName [] . doE' $
    foldl appE (conOfStruct struct) fdefs

defaultOfUnion :: Union a -> Compiler a [Decl]
defaultOfUnion union = do
  let
    funName = nameOfUnionDefault union
    funT = typeOfUnion union
  case union ^. fields of
    [] ->
      hoistCE $ UnionIsUninhabited union
    (field:_) -> do
      fdef <- defaultOfFieldType field
      pure . inlineFunDT funT funName [] . doE' $
        conOfUnionAlt union field `appE` fdef

defaultOfEnum :: Enum a -> Compiler a [Decl]
defaultOfEnum enum = do
  let
    funName = nameOfEnumDefault enum
    funT = typeOfEnum enum
  case enum ^. values of
    [] ->
      hoistCE $ EnumIsUninhabited enum
    (val:_) -> do
      pure . inlineFunDT funT funName [] . doE' $
        conOfEnumAlt enum val

defaultOfType :: Thrift.Type a -> Compiler a [Decl]
defaultOfType = \case
  TypedefType x ->
    hoistCE (TypedefNotSupported x)
  EnumType x ->
    defaultOfEnum x
  StructType x ->
    defaultOfStruct x
  UnionType x ->
    defaultOfUnion x
  SenumType x ->
    hoistCE (SenumDeprecated x)
  ExceptionType x ->
    hoistCE (ExceptionNotSupported x)

defaultOfDefinition :: Definition a -> Compiler a [Decl]
defaultOfDefinition = \case
  ConstDefinition x ->
    hoistCE (ConstNotSupported x)
  ServiceDefinition x ->
    hoistCE (ServiceNotSupported x)
  TypeDefinition x ->
    defaultOfType x
