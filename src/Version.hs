{-# LANGUAGE OverloadedStrings #-}

module Version
  ( assertCompatibleWithPathPin
  ) where

import OurPrelude

import qualified Data.Text as T
import Utils

notElemOf :: (Eq a, Foldable t) => t a -> a -> Bool
notElemOf o = not . flip elem o

-- | Similar to @breakOn@, but will not keep the pattern at the beginning of the suffix.
--
-- Examples:
--
-- >>> clearBreakOn "::" "a::b::c"
-- ("a","b::c")
clearBreakOn :: Text -> Text -> (Text, Text)
clearBreakOn boundary string =
  let (prefix, suffix) = T.breakOn boundary string
   in if T.null suffix
        then (prefix, suffix)
        else (prefix, T.drop (T.length boundary) suffix)

-- | Check if attribute path is not pinned to a certain version.
-- If a derivation is expected to stay at certain version branch,
-- it will usually have the branch as a part of the attribute path.
--
-- Examples:
--
-- >>> versionCompatibleWithPathPin "libgit2_0_25" "0.25.3"
-- True
--
-- >>> versionCompatibleWithPathPin "owncloud90" "9.0.3"
-- True
--
-- >>> versionCompatibleWithPathPin "owncloud-client" "2.4.1"
-- True
--
-- >>> versionCompatibleWithPathPin "owncloud90" "9.1.3"
-- False
--
-- >>> versionCompatibleWithPathPin "nodejs-slim-10_x" "11.2.0"
-- False
--
-- >>> versionCompatibleWithPathPin "nodejs-slim-10_x" "10.12.0"
-- True
versionCompatibleWithPathPin :: Text -> Version -> Bool
versionCompatibleWithPathPin attrPath newVer
  | "_x" `T.isSuffixOf` T.toLower attrPath =
    versionCompatibleWithPathPin (T.dropEnd 2 attrPath) newVer
  | "_" `T.isInfixOf` attrPath =
    let attrVersionPart =
          let (_, version) = clearBreakOn "_" attrPath
           in if T.any (notElemOf ('_' : ['0' .. '9'])) version
                then Nothing
                else Just version
        -- Check assuming version part has underscore separators
        attrVersionPeriods = T.replace "_" "." <$> attrVersionPart
        -- If we don't find version numbers in the attr path, exit success.
     in maybe True (`T.isPrefixOf` newVer) attrVersionPeriods
  | otherwise =
    let attrVersionPart =
          let version = T.dropWhile (notElemOf ['0' .. '9']) attrPath
           in if T.any (notElemOf ['0' .. '9']) version
                then Nothing
                else Just version
          -- Check assuming version part is the prefix of the version with dots
          -- removed. For example, 91 => "9.1"
        noPeriodNewVersion = T.replace "." "" newVer
          -- If we don't find version numbers in the attr path, exit success.
     in maybe True (`T.isPrefixOf` noPeriodNewVersion) attrVersionPart

versionIncompatibleWithPathPin :: Text -> Version -> Bool
versionIncompatibleWithPathPin path version =
  not (versionCompatibleWithPathPin path version)

assertCompatibleWithPathPin :: Monad m => UpdateEnv -> Text -> ExceptT Text m ()
assertCompatibleWithPathPin ue attrPath =
  tryAssert
    ("Version in attr path " <> attrPath <> " not compatible with " <>
     newVersion ue)
    (not
       (versionCompatibleWithPathPin attrPath (oldVersion ue) &&
        versionIncompatibleWithPathPin attrPath (newVersion ue)))
