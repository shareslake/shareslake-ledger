{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingVia #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuantifiedConstraints #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}

-- |
-- Module      : LedgerState
-- Description : Operational Rules
--
-- This module implements the operation rules for treating UTxO transactions ('Tx')
-- as state transformations on a ledger state ('LedgerState'),
-- as specified in /A Simplified Formal Specification of a UTxO Ledger/.
module Cardano.Ledger.Shelley.LedgerState
  ( AccountState (..),
    DPState (..),
    DState (..),
    emptyDState,
    rewards,
    delegations,
    ptrsMap,
    EpochState (..),
    UpecState (..),
    PulsingRewUpdate (..),
    FutureGenDeleg (..),
    InstantaneousRewards (..),
    KeyPairs,
    LedgerState (..),
    PPUPState (..),
    PState (..),
    RewardAccounts,
    RewardUpdate (..),
    RewardSnapShot (..),
    UTxOState (..),
    smartUTxOState,
    IncrementalStake (..),
    depositPoolChange,
    emptyRewardUpdate,
    pvCanFollow,
    reapRewards,
    availableAfterMIR,

    -- * Genesis State
    genesisState,

    -- * Validation
    WitHashes (..),
    nullWitHashes,
    diffWitHashes,
    minfee,
    txsizeBound,
    produced,
    consumed,
    witsFromTxWitnesses,
    propWits,

    -- * DelegationState
    keyRefunds,

    -- * Epoch boundary
    incrementalStakeDistr,
    updateStakeDistribution,
    applyRUpd,
    applyRUpd',
    filterAllRewards,
    createRUpd,
    completeRupd,
    startStep,
    pulseStep,
    completeStep,
    NewEpochState (NewEpochState, nesEL, nesEs, nesRu, nesPd, nesBprev, nesBcur),
    StashedAVVMAddresses,
    stashedAVVMAddresses,
    getGKeys,
    updateNES,
    circulation,

    -- * Decay
    decayFactor,

    -- * Remove Bootstrap Redeem Addresses
    returnRedeemAddrsToReserves,
    updateNonMyopic,
  )
where

import Cardano.Binary
  ( FromCBOR (..),
    ToCBOR (..),
    encodeListLen,
  )
import Cardano.Ledger.Address (Addr (..), isBootstrapRedeemer)
import Cardano.Ledger.BaseTypes
  ( ActiveSlotCoeff,
    BlocksMade (..),
    BoundedRational (..),
    NonNegativeInterval,
    ProtVer (..),
    ShelleyBase,
    StrictMaybe (..),
    UnitInterval,
    activeSlotVal,
  )
import Cardano.Ledger.Coin
  ( Coin (..),
    DeltaCoin (..),
    addDeltaCoin,
    rationalToCoinViaFloor,
    toDeltaCoin,
  )
import Cardano.Ledger.Compactible
import Cardano.Ledger.Core (PParamsDelta)
import qualified Cardano.Ledger.Core as Core
import Cardano.Ledger.Credential (Credential (..), StakeReference (StakeRefBase, StakeRefPtr))
import qualified Cardano.Ledger.Crypto as CC (Crypto)
import Cardano.Ledger.Era (Era (..), getTxOutBootstrapAddress)
import Cardano.Ledger.Keys
  ( GenDelegPair (..),
    GenDelegs (..),
    KeyHash (..),
    KeyPair,
    KeyRole (..),
    asWitness,
  )
import Cardano.Ledger.PoolDistr (PoolDistr (..))
import Cardano.Ledger.SafeHash (HashAnnotated)
import Cardano.Ledger.Serialization (decodeRecordNamedT, mapFromCBOR, mapToCBOR)
import Cardano.Ledger.Shelley (ShelleyEra)
import Cardano.Ledger.Shelley.Address.Bootstrap
  ( BootstrapWitness (..),
    bootstrapWitKeyHash,
  )
import Cardano.Ledger.Shelley.Constraints (TransValue)
import Cardano.Ledger.Shelley.Delegation.Certificates (DCert (..), isDeRegKey)
import Cardano.Ledger.Shelley.EpochBoundary
  ( SnapShot (..),
    SnapShots (..),
    Stake (..),
    sumAllStake,
    sumStakePerPool,
  )
import qualified Cardano.Ledger.Shelley.HardForks as HardForks
import Cardano.Ledger.Shelley.PParams
  ( PParams,
    PParams' (..),
    ProposedPPUpdates (..),
    Update (..),
    emptyPPPUpdates,
  )
import Cardano.Ledger.Shelley.PoolRank
  ( Likelihood (..),
    NonMyopic (..),
    applyDecay,
    leaderProbability,
    likelihood,
  )
import Cardano.Ledger.Shelley.RewardProvenance (RewardProvenance (..))
import qualified Cardano.Ledger.Shelley.RewardProvenance as RP
import Cardano.Ledger.Shelley.RewardUpdate
  ( FreeVars (..),
    Pulser,
    PulsingRewUpdate (..),
    RewardAns (..),
    RewardEvent,
    RewardPulser (..),
    RewardSnapShot (..),
    RewardUpdate (..),
    emptyRewardUpdate,
  )
import Cardano.Ledger.Shelley.Rewards
  ( PoolRewardInfo (..),
    Reward (..),
    StakeShare (..),
    aggregateRewards,
    filterRewards,
    leaderRewardToGeneral,
    mkPoolRewardInfo,
    sumRewards,
  )
import Cardano.Ledger.Shelley.TxBody
  ( EraIndependentTxBody,
    MIRPot (..),
    PoolParams (..),
    Ptr (..),
    RewardAcnt (..),
    Wdrl (..),
    WitVKey (..),
    getRwdCred,
    witKeyHash,
  )
import Cardano.Ledger.Shelley.UTxO
  ( UTxO (..),
    balance,
    totalDeposits,
    txins,
    txouts,
  )
import Cardano.Ledger.Slot
  ( EpochNo (..),
    EpochSize (..),
    SlotNo (..),
  )
import Cardano.Ledger.TxIn (TxIn (..))
import Cardano.Ledger.UnifiedMap (Trip (..), Triple, UMap (..), UnifiedMap, View (..), ViewMap)
import Cardano.Ledger.Val ((<+>), (<->), (<×>))
import qualified Cardano.Ledger.Val as Val
import Cardano.Prelude (rightToMaybe)
import Control.DeepSeq (NFData)
import Control.Monad.State.Strict (evalStateT)
import Control.Monad.Trans
import Control.Provenance (ProvM, modifyM, runProvM)
import Control.SetAlgebra (dom, eval, (∈), (◁))
import Control.State.Transition (STS (State))
import Data.Coders
  ( Decode (From, RecD),
    decode,
    decodeRecordNamed,
    (<!),
  )
import qualified Data.Compact.SplitMap as SplitMap
import qualified Data.Compact.VMap as VMap
import Data.Default.Class (Default, def)
import Data.Foldable (fold, toList)
import Data.Group (Group, invert)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Pulse (Pulsable (..), completeM)
import Data.Ratio ((%))
import Data.Sequence.Strict (StrictSeq)
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Sharing
import Data.Typeable
import qualified Data.UMap as UM
import Data.Word (Word64)
import GHC.Generics (Generic)
import GHC.Records (HasField (..))
import Lens.Micro (_1, _2)
import NoThunks.Class (NoThunks (..))
import Numeric.Natural (Natural)
import Quiet

-- | Representation of a list of pairs of key pairs, e.g., pay and stake keys
type KeyPairs crypto = [(KeyPair 'Payment crypto, KeyPair 'Staking crypto)]

type RewardAccounts crypto =
  Map (Credential 'Staking crypto) Coin

data FutureGenDeleg crypto = FutureGenDeleg
  { fGenDelegSlot :: !SlotNo,
    fGenDelegGenKeyHash :: !(KeyHash 'Genesis crypto)
  }
  deriving (Show, Eq, Ord, Generic)

instance NoThunks (FutureGenDeleg crypto)

instance NFData (FutureGenDeleg crypto)

instance CC.Crypto crypto => ToCBOR (FutureGenDeleg crypto) where
  toCBOR (FutureGenDeleg a b) =
    encodeListLen 2 <> toCBOR a <> toCBOR b

instance CC.Crypto crypto => FromCBOR (FutureGenDeleg crypto) where
  fromCBOR =
    decodeRecordNamed "FutureGenDeleg" (const 2) $
      FutureGenDeleg <$> fromCBOR <*> fromCBOR

-- | InstantaneousRewards captures the pending changes to the ledger
-- state caused by MIR certificates. It consists of two mappings,
-- the rewards which will be paid out from the reserves and the rewards
-- which will be paid out from the treasury. It also consists of
-- two coin values which represent the transfer of coins from
-- one pot to the other pot.
-- NOTE that the following property should always hold:
--   deltaReserves + deltaTreasury = 0
data InstantaneousRewards crypto = InstantaneousRewards
  { iRReserves :: !(Map (Credential 'Staking crypto) Coin),
    iRTreasury :: !(Map (Credential 'Staking crypto) Coin),
    deltaReserves :: !DeltaCoin,
    deltaTreasury :: !DeltaCoin
  }
  deriving (Show, Eq, Generic)

-- | This function returns the coin balance of a given pot, either the
-- reserves or the treasury, after the instantaneous rewards and pot
-- transfers are accounted for.
availableAfterMIR :: MIRPot -> AccountState -> InstantaneousRewards crypto -> Coin
availableAfterMIR ReservesMIR as ir =
  _reserves as `addDeltaCoin` deltaReserves ir <-> fold (iRReserves ir)
availableAfterMIR TreasuryMIR as ir =
  _treasury as `addDeltaCoin` deltaTreasury ir <-> fold (iRTreasury ir)

instance NoThunks (InstantaneousRewards crypto)

instance NFData (InstantaneousRewards crypto)

instance CC.Crypto crypto => ToCBOR (InstantaneousRewards crypto) where
  toCBOR (InstantaneousRewards irR irT dR dT) =
    encodeListLen 4 <> mapToCBOR irR <> mapToCBOR irT <> toCBOR dR <> toCBOR dT

instance CC.Crypto crypto => FromSharedCBOR (InstantaneousRewards crypto) where
  type Share (InstantaneousRewards crypto) = Interns (Credential 'Staking crypto)
  fromSharedPlusCBOR = do
    decodeRecordNamedT "InstantaneousRewards" (const 4) $ do
      irR <- fromSharedPlusLensCBOR (toMemptyLens _1 id)
      irT <- fromSharedPlusLensCBOR (toMemptyLens _1 id)
      dR <- lift fromCBOR
      dT <- lift fromCBOR
      pure $ InstantaneousRewards irR irT dR dT

-- | State of staking pool delegations and rewards
data DState crypto = DState
  { -- | Unified Reward Maps
    _unified :: !(UnifiedMap crypto),
    -- | Future genesis key delegations
    _fGenDelegs :: !(Map (FutureGenDeleg crypto) (GenDelegPair crypto)),
    -- | Genesis key delegations
    _genDelegs :: !(GenDelegs crypto),
    -- | Instantaneous Rewards
    _irwd :: !(InstantaneousRewards crypto)
  }
  deriving (Show, Eq, Generic)

-- ========================
-- Virtual selectors, which get the appropriate view from a DState from the embedded UnifiedMap

rewards :: DState crypto -> ViewMap crypto (Credential 'Staking crypto) Coin
rewards (DState unified _ _ _) = Rewards unified

delegations ::
  DState crypto ->
  ViewMap crypto (Credential 'Staking crypto) (KeyHash 'StakePool crypto)
delegations (DState unified _ _ _) = Delegations unified

-- | get the actual ptrs map, we don't need a view
ptrsMap :: DState crypto -> Map Ptr (Credential 'Staking crypto)
ptrsMap (DState (UnifiedMap _ ptrmap) _ _ _) = ptrmap

-- =======================
-- CBOR instances

instance NoThunks (DState crypto)

instance NFData (DState crypto)

instance CC.Crypto crypto => ToCBOR (DState crypto) where
  toCBOR (DState unified fgs gs ir) =
    encodeListLen 4
      <> toCBOR unified
      <> toCBOR fgs
      <> toCBOR gs
      <> toCBOR ir

instance CC.Crypto crypto => FromSharedCBOR (DState crypto) where
  type
    Share (DState crypto) =
      (Interns (Credential 'Staking crypto), Interns (KeyHash 'StakePool crypto))
  fromSharedPlusCBOR = do
    decodeRecordNamedT "DState" (const 4) $ do
      unified <- fromSharedPlusCBOR
      fgs <- lift fromCBOR
      gs <- lift fromCBOR
      ir <- fromSharedPlusLensCBOR _1
      pure $ DState unified fgs gs ir

-- | Current state of staking pools and their certificate counters.
data PState crypto = PState
  { -- | The pool parameters.
    _pParams :: !(Map (KeyHash 'StakePool crypto) (PoolParams crypto)),
    -- | The future pool parameters.
    _fPParams :: !(Map (KeyHash 'StakePool crypto) (PoolParams crypto)),
    -- | A map of retiring stake pools to the epoch when they retire.
    _retiring :: !(Map (KeyHash 'StakePool crypto) EpochNo)
  }
  deriving (Show, Eq, Generic)

instance NoThunks (PState crypto)

instance NFData (PState crypto)

instance CC.Crypto crypto => ToCBOR (PState crypto) where
  toCBOR (PState a b c) =
    encodeListLen 3 <> toCBOR a <> toCBOR b <> toCBOR c

instance CC.Crypto crypto => FromSharedCBOR (PState crypto) where
  type
    Share (PState crypto) =
      Interns (KeyHash 'StakePool crypto)
  fromSharedPlusCBOR = decodeRecordNamedT "PState" (const 3) $ do
    _pParams <- fromSharedPlusLensCBOR (toMemptyLens _1 id)
    _fPParams <- fromSharedPlusLensCBOR (toMemptyLens _1 id)
    _retiring <- fromSharedPlusLensCBOR (toMemptyLens _1 id)
    pure PState {_pParams, _fPParams, _retiring}

-- | The state associated with the current stake delegation.
data DPState crypto = DPState
  { dpsDState :: !(DState crypto),
    dpsPState :: !(PState crypto)
  }
  deriving (Show, Eq, Generic)

instance NoThunks (DPState crypto)

instance NFData (DPState crypto)

instance
  CC.Crypto crypto =>
  ToCBOR (DPState crypto)
  where
  toCBOR DPState {dpsPState, dpsDState} =
    encodeListLen 2
      <> toCBOR dpsPState -- We get better sharing when encoding pstate before dstate
      <> toCBOR dpsDState

instance CC.Crypto crypto => FromSharedCBOR (DPState crypto) where
  type
    Share (DPState crypto) =
      ( Interns (Credential 'Staking crypto),
        Interns (KeyHash 'StakePool crypto)
      )
  fromSharedPlusCBOR = decodeRecordNamedT "DPState" (const 2) $ do
    dpsPState <- fromSharedPlusLensCBOR _2
    dpsDState <- fromSharedPlusCBOR
    pure DPState {dpsPState, dpsDState}

data AccountState = AccountState
  { _treasury :: !Coin,
    _reserves :: !Coin
  }
  deriving (Show, Eq, Generic)

instance ToCBOR AccountState where
  toCBOR (AccountState t r) =
    encodeListLen 2 <> toCBOR t <> toCBOR r

instance FromCBOR AccountState where
  fromCBOR =
    decodeRecordNamed "AccountState" (const 2) $ AccountState <$> fromCBOR <*> fromCBOR

instance NoThunks AccountState

instance NFData AccountState

data EpochState era = EpochState
  { esAccountState :: !AccountState,
    esSnapshots :: !(SnapShots (Crypto era)),
    esLState :: !(LedgerState era),
    esPrevPp :: !(Core.PParams era),
    esPp :: !(Core.PParams era),
    -- | This field, esNonMyopic, does not appear in the formal spec
    -- and is not a part of the protocol. It is only used for providing
    -- data to the stake pool ranking calculation @getNonMyopicMemberRewards@.
    -- See https://hydra.iohk.io/job/Cardano/cardano-ledger-specs/specs.pool-ranking/latest/download-by-type/doc-pdf/pool-ranking
    esNonMyopic :: !(NonMyopic (Crypto era))
  }
  deriving (Generic)

deriving stock instance
  ( CC.Crypto (Crypto era),
    Show (Core.TxOut era),
    Show (Core.PParams era),
    Show (State (Core.EraRule "PPUP" era))
  ) =>
  Show (EpochState era)

deriving stock instance
  ( CC.Crypto (Crypto era),
    Eq (Core.TxOut era),
    Eq (Core.PParams era),
    Eq (State (Core.EraRule "PPUP" era))
  ) =>
  Eq (EpochState era)

instance
  ( Era era,
    NoThunks (Core.TxOut era),
    NoThunks (State (Core.EraRule "PPUP" era)),
    NoThunks (Core.Value era),
    NoThunks (Core.PParams era),
    ToCBOR (Core.TxBody era),
    ToCBOR (Core.TxOut era),
    ToCBOR (Core.Value era)
  ) =>
  NoThunks (EpochState era)

instance
  ( Era era,
    NFData (Core.TxOut era),
    NFData (Core.PParams era),
    NFData (State (Core.EraRule "PPUP" era))
  ) =>
  NFData (EpochState era)

instance
  ( Era era,
    ToCBOR (Core.TxOut era),
    ToCBOR (Core.PParams era),
    ToCBOR (State (Core.EraRule "PPUP" era))
  ) =>
  ToCBOR (EpochState era)
  where
  toCBOR EpochState {esAccountState, esLState, esSnapshots, esPrevPp, esPp, esNonMyopic} =
    encodeListLen 6
      <> toCBOR esAccountState
      <> toCBOR esLState -- We get better sharing when encoding ledger state before snaphots
      <> toCBOR esSnapshots
      <> toCBOR esPrevPp
      <> toCBOR esPp
      <> toCBOR esNonMyopic

instance
  ( FromCBOR (Core.PParams era),
    TransValue FromCBOR era,
    HashAnnotated (Core.TxBody era) EraIndependentTxBody (Crypto era),
    FromSharedCBOR (Core.TxOut era),
    Share (Core.TxOut era) ~ Interns (Credential 'Staking (Crypto era)),
    FromCBOR (State (Core.EraRule "PPUP" era)),
    Era era
  ) =>
  FromCBOR (EpochState era)
  where
  fromCBOR =
    decodeRecordNamed "EpochState" (const 6) $
      flip evalStateT mempty $ do
        esAccountState <- lift fromCBOR
        esLState <- fromSharedPlusCBOR
        esSnapshots <- fromSharedPlusCBOR
        esPrevPp <- lift fromCBOR
        esPp <- lift fromCBOR
        esNonMyopic <- fromSharedLensCBOR _2
        pure EpochState {esAccountState, esSnapshots, esLState, esPrevPp, esPp, esNonMyopic}

data UpecState era = UpecState
  { -- | Current protocol parameters.
    currentPp :: !(Core.PParams era),
    -- | State of the protocol update transition system.
    ppupState :: !(State (Core.EraRule "PPUP" era))
  }

deriving stock instance
  ( Show (State (Core.EraRule "PPUP" era)),
    Show (Core.PParams era)
  ) =>
  Show (UpecState era)

data PPUPState era = PPUPState
  { proposals :: !(ProposedPPUpdates era),
    futureProposals :: !(ProposedPPUpdates era)
  }
  deriving (Generic)

deriving instance Show (PParamsDelta era) => Show (PPUPState era)

deriving instance Eq (PParamsDelta era) => Eq (PPUPState era)

deriving instance NFData (PParamsDelta era) => NFData (PPUPState era)

instance NoThunks (PParamsDelta era) => NoThunks (PPUPState era)

instance (Era era, ToCBOR (PParamsDelta era)) => ToCBOR (PPUPState era) where
  toCBOR (PPUPState ppup fppup) =
    encodeListLen 2 <> toCBOR ppup <> toCBOR fppup

instance
  (Era era, FromCBOR (PParamsDelta era)) =>
  FromCBOR (PPUPState era)
  where
  fromCBOR =
    decode $
      RecD PPUPState
        <! From
        <! From

pvCanFollow :: ProtVer -> StrictMaybe ProtVer -> Bool
pvCanFollow _ SNothing = True
pvCanFollow (ProtVer m n) (SJust (ProtVer m' n')) =
  (m + 1, 0) == (m', n') || (m, n + 1) == (m', n')

-- =============================

-- | Incremental Stake, Stake along with possible missed coins from danging Ptrs.
--   Transactions can use Ptrs to refer to a stake credential in a TxOut. The Ptr
--   does not have to point to anything until the epoch boundary, when we compute
--   rewards and aggregate staking information for ranking. This is unusual but legal.
--   In a non incremental system, we use whatever 'legal' Ptrs exist at the epoch
--   boundary. Here we are computing things incrementally, so we need to remember Ptrs
--   that might point to something by the time the epoch boundary is reached. When
--   the epoch boundary is reached we 'resolve' these pointers, to see if any have
--   become non-dangling since the time they were first used in the incremental computation.
data IncrementalStake crypto = IStake
  { credMap :: !(Map (Credential 'Staking crypto) Coin),
    ptrMap :: !(Map Ptr Coin)
  }
  deriving (Generic, Show, Eq, Ord, NoThunks, NFData)

instance CC.Crypto crypto => ToCBOR (IncrementalStake crypto) where
  toCBOR (IStake st dangle) =
    encodeListLen 2 <> mapToCBOR st <> mapToCBOR dangle

instance CC.Crypto crypto => FromSharedCBOR (IncrementalStake crypto) where
  type Share (IncrementalStake crypto) = Interns (Credential 'Staking crypto)
  fromSharedCBOR credInterns = do
    decodeRecordNamed "Stake" (const 2) $ do
      stake <- fromSharedCBOR (credInterns, mempty)
      dangle <- mapFromCBOR
      pure $ IStake stake dangle

instance Semigroup (IncrementalStake c) where
  (IStake a b) <> (IStake c d) = IStake (Map.unionWith (<>) a c) (Map.unionWith (<>) b d)

instance Monoid (IncrementalStake c) where
  mempty = IStake Map.empty Map.empty

instance Data.Group.Group (IncrementalStake c) where
  invert (IStake m1 m2) = IStake (Map.map invert m1) (Map.map invert m2)

instance Default (IncrementalStake c) where
  def = IStake Map.empty Map.empty

-- =============================

-- | There is a serious invariant that we must maintain in the UTxOState.
--   Given (UTxOState utxo _ _ _ istake) it must be the case that
--   istake == (updateStakeDistribution (UTxO SplitMap.empty) (UTxO SplitMap.empty) utxo)
--   Of course computing the RHS of the above equality can be very expensive, so we only
--   use this route in the testing function smartUTxO. But we are very carefull, wherever
--   we update the UTxO, we carefully make INCREMENTAL changes to istake to maintain
--   this invariant. This happens in the UTxO rule.
data UTxOState era = UTxOState
  { _utxo :: !(UTxO era),
    _deposited :: !Coin,
    _fees :: !Coin,
    _ppups :: !(State (Core.EraRule "PPUP" era)),
    _stakeDistro :: !(IncrementalStake (Crypto era))
  }
  deriving (Generic)

instance
  ( Era era,
    NFData (Core.TxOut era),
    NFData (State (Core.EraRule "PPUP" era))
  ) =>
  NFData (UTxOState era)

deriving stock instance
  ( CC.Crypto (Crypto era),
    Show (Core.TxOut era),
    Show (State (Core.EraRule "PPUP" era))
  ) =>
  Show (UTxOState era)

deriving stock instance
  ( CC.Crypto (Crypto era),
    Eq (Core.TxOut era),
    Eq (State (Core.EraRule "PPUP" era))
  ) =>
  Eq (UTxOState era)

instance
  ( Era era,
    NoThunks (Core.TxOut era),
    NoThunks (State (Core.EraRule "PPUP" era)),
    NoThunks (Core.Value era),
    ToCBOR (Core.TxBody era),
    ToCBOR (Core.TxOut era),
    ToCBOR (Core.Value era)
  ) =>
  NoThunks (UTxOState era)

instance
  ( Era era,
    ToCBOR (Core.TxOut era),
    ToCBOR (State (Core.EraRule "PPUP" era))
  ) =>
  ToCBOR (UTxOState era)
  where
  toCBOR (UTxOState ut dp fs us sd) =
    encodeListLen 5 <> toCBOR ut <> toCBOR dp <> toCBOR fs <> toCBOR us <> toCBOR sd

instance
  ( TransValue FromCBOR era,
    FromCBOR (State (Core.EraRule "PPUP" era)),
    FromSharedCBOR (Core.TxOut era),
    Share (Core.TxOut era) ~ Interns (Credential 'Staking (Crypto era)),
    HashAnnotated (Core.TxBody era) EraIndependentTxBody (Crypto era)
  ) =>
  FromSharedCBOR (UTxOState era)
  where
  type
    Share (UTxOState era) =
      Interns (Credential 'Staking (Crypto era))
  fromSharedCBOR credInterns =
    decodeRecordNamed "UTxOState" (const 5) $ do
      _utxo <- fromSharedCBOR credInterns
      _deposited <- fromCBOR
      _fees <- fromCBOR
      _ppups <- fromCBOR
      _stakeDistro <- fromSharedCBOR credInterns
      pure UTxOState {_utxo, _deposited, _fees, _ppups, _stakeDistro}

-- | New Epoch state and environment
data NewEpochState era = NewEpochState
  { -- | Last epoch
    nesEL :: !EpochNo,
    -- | Blocks made before current epoch
    nesBprev :: !(BlocksMade (Crypto era)),
    -- | Blocks made in current epoch
    nesBcur :: !(BlocksMade (Crypto era)),
    -- | Epoch state before current
    nesEs :: !(EpochState era),
    -- | Possible reward update
    nesRu :: !(StrictMaybe (PulsingRewUpdate (Crypto era))),
    -- | Stake distribution within the stake pool
    nesPd :: !(PoolDistr (Crypto era)),
    -- | AVVM addresses to be removed at the end of the Shelley era. Note that
    -- the existence of this field is a hack, related to the transition of UTxO
    -- to disk. We remove AVVM addresses from the UTxO on the Shelley/Allegra
    -- boundary. However, by this point the UTxO will be moved to disk, and
    -- hence doing a scan of the UTxO for AVVM addresses will be expensive. Our
    -- solution to this is to do a scan of the UTxO on the Byron/Shelley
    -- boundary (since Byron UTxO are still on disk), stash the results here,
    -- and then remove them at the Shelley/Allegra boundary.
    --
    -- This is very much an awkward implementation hack, and hence we hide it
    -- from as many places as possible.
    stashedAVVMAddresses :: !(StashedAVVMAddresses era)
  }
  deriving (Generic)

type family StashedAVVMAddresses era where
  StashedAVVMAddresses (ShelleyEra c) = UTxO (ShelleyEra c)
  StashedAVVMAddresses _ = ()

deriving stock instance
  ( CC.Crypto (Crypto era),
    Show (Core.TxOut era),
    Show (Core.PParams era),
    Show (State (Core.EraRule "PPUP" era)),
    Show (StashedAVVMAddresses era)
  ) =>
  Show (NewEpochState era)

deriving stock instance
  ( CC.Crypto (Crypto era),
    Eq (Core.TxOut era),
    Eq (Core.PParams era),
    Eq (State (Core.EraRule "PPUP" era)),
    Eq (StashedAVVMAddresses era)
  ) =>
  Eq (NewEpochState era)

instance
  ( Era era,
    NFData (Core.TxOut era),
    NFData (Core.PParams era),
    NFData (State (Core.EraRule "PPUP" era)),
    NFData (StashedAVVMAddresses era)
  ) =>
  NFData (NewEpochState era)

instance
  ( Era era,
    NoThunks (Core.TxOut era),
    NoThunks (Core.PParams era),
    NoThunks (State (Core.EraRule "PPUP" era)),
    NoThunks (Core.Value era),
    NoThunks (StashedAVVMAddresses era),
    ToCBOR (Core.TxBody era),
    ToCBOR (Core.TxOut era),
    ToCBOR (Core.Value era)
  ) =>
  NoThunks (NewEpochState era)

instance
  ( Era era,
    ToCBOR (Core.TxOut era),
    ToCBOR (Core.PParams era),
    ToCBOR (State (Core.EraRule "PPUP" era)),
    ToCBOR (StashedAVVMAddresses era)
  ) =>
  ToCBOR (NewEpochState era)
  where
  toCBOR (NewEpochState e bp bc es ru pd av) =
    encodeListLen 7
      <> toCBOR e
      <> toCBOR bp
      <> toCBOR bc
      <> toCBOR es
      <> toCBOR ru
      <> toCBOR pd
      <> toCBOR av

instance
  ( Era era,
    FromCBOR (Core.PParams era),
    FromSharedCBOR (Core.TxOut era),
    Share (Core.TxOut era) ~ Interns (Credential 'Staking (Crypto era)),
    FromCBOR (Core.Value era),
    FromCBOR (State (Core.EraRule "PPUP" era)),
    FromCBOR (StashedAVVMAddresses era)
  ) =>
  FromCBOR (NewEpochState era)
  where
  fromCBOR = do
    decode $
      RecD NewEpochState
        <! From
        <! From
        <! From
        <! From
        <! From
        <! From
        <! From

getGKeys ::
  NewEpochState era ->
  Set (KeyHash 'Genesis (Crypto era))
getGKeys nes = Map.keysSet genDelegs
  where
    NewEpochState _ _ _ es _ _ _ = nes
    EpochState _ _ ls _ _ _ = es
    LedgerState _ (DPState (DState _ _ (GenDelegs genDelegs) _) _) = ls

-- | The state associated with a 'Ledger'.
data LedgerState era = LedgerState
  { -- | The current unspent transaction outputs.
    lsUTxOState :: !(UTxOState era),
    -- | The current delegation state
    lsDPState :: !(DPState (Crypto era))
  }
  deriving (Generic)

deriving stock instance
  ( CC.Crypto (Crypto era),
    Show (Core.TxOut era),
    Show (State (Core.EraRule "PPUP" era))
  ) =>
  Show (LedgerState era)

deriving stock instance
  ( CC.Crypto (Crypto era),
    Eq (Core.TxOut era),
    Eq (State (Core.EraRule "PPUP" era))
  ) =>
  Eq (LedgerState era)

instance
  ( Era era,
    NoThunks (Core.TxOut era),
    NoThunks (State (Core.EraRule "PPUP" era)),
    NoThunks (Core.Value era),
    ToCBOR (Core.TxBody era),
    ToCBOR (Core.TxOut era),
    ToCBOR (Core.Value era)
  ) =>
  NoThunks (LedgerState era)

instance
  ( Era era,
    NFData (Core.TxOut era),
    NFData (State (Core.EraRule "PPUP" era))
  ) =>
  NFData (LedgerState era)

instance
  ( Era era,
    ToCBOR (Core.TxOut era),
    ToCBOR (State (Core.EraRule "PPUP" era))
  ) =>
  ToCBOR (LedgerState era)
  where
  toCBOR LedgerState {lsUTxOState, lsDPState} =
    encodeListLen 2
      <> toCBOR lsDPState -- encode delegation state first to improve sharing
      <> toCBOR lsUTxOState

instance
  ( Era era,
    HashAnnotated (Core.TxBody era) EraIndependentTxBody (Crypto era),
    FromCBOR (Core.Value era),
    FromSharedCBOR (Core.TxOut era),
    Share (Core.TxOut era) ~ Interns (Credential 'Staking (Crypto era)),
    FromCBOR (State (Core.EraRule "PPUP" era))
  ) =>
  FromSharedCBOR (LedgerState era)
  where
  type
    Share (LedgerState era) =
      (Interns (Credential 'Staking (Crypto era)), Interns (KeyHash 'StakePool (Crypto era)))
  fromSharedPlusCBOR =
    decodeRecordNamedT "LedgerState" (const 2) $ do
      lsDPState <- fromSharedPlusCBOR
      lsUTxOState <- fromSharedLensCBOR _1
      pure LedgerState {lsUTxOState, lsDPState}

-- | Creates the ledger state for an empty ledger which
--  contains the specified transaction outputs.
genesisState ::
  Default (State (Core.EraRule "PPUP" era)) =>
  Map (KeyHash 'Genesis (Crypto era)) (GenDelegPair (Crypto era)) ->
  UTxO era ->
  LedgerState era
genesisState genDelegs0 utxo0 =
  LedgerState
    ( UTxOState
        utxo0
        (Coin 0)
        (Coin 0)
        def
        (IStake mempty Map.empty)
    )
    (DPState dState def)
  where
    dState = def {_genDelegs = GenDelegs genDelegs0}

-- | Convenience Function to bound the txsize function.
-- | It can be helpful for coin selection.
txsizeBound ::
  forall era out tx.
  ( HasField "outputs" (Core.TxBody era) (StrictSeq out),
    HasField "inputs" (Core.TxBody era) (Set (TxIn (Crypto era))),
    HasField "body" tx (Core.TxBody era),
    HasField "txsize" tx Integer
  ) =>
  Proxy era ->
  tx ->
  Integer
txsizeBound Proxy tx = numInputs * inputSize + numOutputs * outputSize + rest
  where
    uint = 5
    smallArray = 1
    hashLen = 32
    hashObj = 2 + hashLen
    addrHashLen = 28
    addrHeader = 1
    address = 2 + addrHeader + 2 * addrHashLen
    txbody = getField @"body" tx
    numInputs = toInteger . length . getField @"inputs" $ txbody
    inputSize = smallArray + uint + hashObj
    numOutputs = toInteger . length . getField @"outputs" $ txbody
    outputSize = smallArray + uint + address
    rest = getField @"txsize" tx

-- | Minimum fee calculation
minfee ::
  ( HasField "_minfeeA" pp Natural,
    HasField "_minfeeB" pp Natural,
    HasField "txsize" tx Integer
  ) =>
  pp ->
  tx ->
  Coin
minfee pp tx =
  Coin $
    fromIntegral (getField @"_minfeeA" pp)
      * getField @"txsize" tx + fromIntegral (getField @"_minfeeB" pp)

-- | Compute the lovelace which are created by the transaction
produced ::
  forall era pp.
  ( Era era,
    HasField "certs" (Core.TxBody era) (StrictSeq (DCert (Crypto era))),
    HasField "_keyDeposit" pp Coin,
    HasField "_poolDeposit" pp Coin
  ) =>
  pp ->
  (KeyHash 'StakePool (Crypto era) -> Bool) ->
  Core.TxBody era ->
  Core.Value era
produced pp isNewPool tx =
  balance (txouts tx)
    <+> Val.inject
      ( getField @"txfee" tx
          <+> totalDeposits pp isNewPool (toList $ getField @"certs" tx)
      )

-- | Compute the key deregistration refunds in a transaction
keyRefunds ::
  ( HasField "certs" txb (StrictSeq (DCert crypto)),
    HasField "_keyDeposit" pp Coin
  ) =>
  pp ->
  txb ->
  Coin
keyRefunds pp tx = length deregistrations <×> getField @"_keyDeposit" pp
  where
    deregistrations = filter isDeRegKey (toList $ getField @"certs" tx)

-- | Compute the lovelace which are destroyed by the transaction
consumed ::
  forall era pp.
  ( Era era,
    HasField "certs" (Core.TxBody era) (StrictSeq (DCert (Crypto era))),
    HasField "inputs" (Core.TxBody era) (Set (TxIn (Crypto era))),
    HasField "wdrls" (Core.TxBody era) (Wdrl (Crypto era)),
    HasField "_keyDeposit" pp Coin
  ) =>
  pp ->
  UTxO era ->
  Core.TxBody era ->
  Core.Value era
consumed pp (UTxO u) tx =
  {- balance (txins tx ◁ u) + wbalance (txwdrls tx) + keyRefunds pp tx -}
  Set.foldl' lookupAddTxOut mempty (txins @era tx)
    <> Val.inject (refunds <+> withdrawals)
  where
    lookupAddTxOut acc txin = maybe acc (addTxOut acc) $ SplitMap.lookup txin u
    addTxOut !b out = getField @"value" out <+> b
    refunds = keyRefunds pp tx
    withdrawals = fold . unWdrl $ getField @"wdrls" tx

-- ====================================================

newtype WitHashes crypto = WitHashes
  {unWitHashes :: Set (KeyHash 'Witness crypto)}
  deriving (Eq, Generic)
  deriving (Show) via Quiet (WitHashes crypto)

instance NoThunks (WitHashes crypto)

-- | Check if a set of witness hashes is empty.
nullWitHashes :: WitHashes crypto -> Bool
nullWitHashes (WitHashes a) = Set.null a

-- | Extract the difference between two sets of witness hashes.
diffWitHashes :: WitHashes crypto -> WitHashes crypto -> WitHashes crypto
diffWitHashes (WitHashes x) (WitHashes x') =
  WitHashes (x `Set.difference` x')

-- | Extract the witness hashes from the Transaction.
witsFromTxWitnesses ::
  ( Era era,
    HasField "addrWits" tx (Set (WitVKey 'Witness (Crypto era))),
    HasField "bootWits" tx (Set (BootstrapWitness (Crypto era)))
  ) =>
  tx ->
  WitHashes (Crypto era)
witsFromTxWitnesses coreTx =
  WitHashes $
    Set.map witKeyHash addWits
      `Set.union` Set.map bootstrapWitKeyHash bsWits
  where
    bsWits = getField @"bootWits" coreTx
    addWits = getField @"addrWits" coreTx

-- | Calculate the set of hash keys of the required witnesses for update
-- proposals.
propWits ::
  Maybe (Update era) ->
  GenDelegs (Crypto era) ->
  Set (KeyHash 'Witness (Crypto era))
propWits Nothing _ = Set.empty
propWits (Just (Update (ProposedPPUpdates pup) _)) (GenDelegs genDelegs) =
  Set.map asWitness . Set.fromList $ Map.elems updateKeys
  where
    updateKeys' = eval (Map.keysSet pup ◁ genDelegs)
    updateKeys = Map.map genDelegKeyHash updateKeys'

-- Functions for stake delegation model

-- | Calculate the change to the deposit pool for a given transaction.
depositPoolChange ::
  ( HasField "certs" (Core.TxBody era) (StrictSeq (DCert (Crypto era)))
  ) =>
  LedgerState era ->
  PParams era ->
  Core.TxBody era ->
  Coin
depositPoolChange ls pp tx = (currentPool <+> txDeposits) <-> txRefunds
  where
    -- Note that while (currentPool + txDeposits) >= txRefunds,
    -- it could be that txDeposits < txRefunds. We keep the parenthesis above
    -- to emphasize this point.

    currentPool = (_deposited . lsUTxOState) ls
    pools = _pParams . dpsPState . lsDPState $ ls
    txDeposits =
      totalDeposits pp (`Map.notMember` pools) (toList $ getField @"certs" tx)
    txRefunds = keyRefunds pp tx

reapRewards ::
  UnifiedMap crypto ->
  RewardAccounts crypto ->
  UnifiedMap crypto
reapRewards (UnifiedMap tmap ptrmap) withdrawals = UnifiedMap (Map.mapWithKey g tmap) ptrmap
  where
    g k (Triple x y z) = Triple (fmap (removeRewards k) x) y z
    removeRewards k v = if k `Map.member` withdrawals then Coin 0 else v

---------------------------------
-- epoch boundary calculations --
---------------------------------

compactCoinOrError :: Coin -> CompactForm Coin
compactCoinOrError c =
  case toCompact c of
    Nothing -> error $ "Invalid ADA value in staking: " <> show c
    Just compactCoin -> compactCoin

-- ==============================
-- operations on IncrementalStake

-- | Incrementally add the inserts 'utxoAdd' and the deletes 'utxoDel' to the IncrementalStake.
updateStakeDistribution ::
  ( Era era
  ) =>
  IncrementalStake (Crypto era) ->
  UTxO era ->
  UTxO era ->
  IncrementalStake (Crypto era)
updateStakeDistribution incStake0 utxoDel utxoAdd = incStake2
  where
    incStake1 = incrementalAggregateUtxoCoinByCredential id utxoAdd incStake0
    incStake2 = incrementalAggregateUtxoCoinByCredential invert utxoDel incStake1

-- | Incrementally sum up all the Coin for each staking Credential, use different 'mode' operations
--   for UTxO that are inserts (id) and UTxO that are deletes (invert). Never store a (Coin 0) balance,
--   since these do not occur in the non-incremental style that works directly from the whole UTxO.
--   This function has a non-incremental analog 'aggregateUtxoCoinByCredential' . In this incremental
--   version we expect the size of the UTxO to be fairly small. I.e the number of inputs and outputs
--   in a transaction, which is aways < 4096, not millions, and very often < 10).
incrementalAggregateUtxoCoinByCredential ::
  forall era.
  Era era =>
  (Coin -> Coin) ->
  UTxO era ->
  IncrementalStake (Crypto era) ->
  IncrementalStake (Crypto era)
incrementalAggregateUtxoCoinByCredential mode (UTxO u) initial =
  SplitMap.foldl' accum initial u
  where
    keepOrDelete new Nothing =
      case mode new of
        Coin 0 -> Nothing
        final -> Just final
    keepOrDelete new (Just old) =
      case mode new <> old of
        Coin 0 -> Nothing
        final -> Just final
    accum ans@(IStake stake ptrs) out =
      let c = Val.coin (getField @"value" out)
       in case getTxOutAddr out of
            Addr _ _ (StakeRefPtr p) -> IStake stake (Map.alter (keepOrDelete c) p ptrs)
            Addr _ _ (StakeRefBase hk) -> IStake (Map.alter (keepOrDelete c) hk stake) ptrs
            _other -> ans

-- A TxOut has 4 different shapes, depending on the shape of its embedded Addr.
-- Credentials are stored in only 2 of the 4 cases.
-- 1) TxOut (Addr _ _ (StakeRefBase cred)) coin   -> HERE
-- 2) TxOut (Addr _ _ (StakeRefPtr ptr)) coin     -> HERE
-- 3) TxOut (Addr _ _ StakeRefNull) coin          -> NOT HERE
-- 4) TxOut (AddrBootstrap _) coin                -> NOT HERE

-- ========================================================================

-- | Compute the current state distribution by using the IncrementalStake,

-- | This computes the stake distribution using IncrementalStake (which is an
--   aggregate of the current UTxO) and UnifiedMap (which tracks Coin,
--   Delegations, and Ptrs simultaneously).  Note that logically:
--   1) IncrementalStake = (credStake, ptrStake)
--   2) UnifiedMap = (rewards, activeDelegs, ptrmap :: Map ptr cred)
--
--   Using this scheme the logic can do 3 things in one go, without touching the UTxO.
--   1) Resolve Pointers
--   2) Throw away things not actively delegated
--   3) Add up the coin
--
--   The Stake distribution function (Map cred coin) (the first component of a SnapShot)
--   is defined by this SetAlgebra expression:
--   (dom activeDelegs) ◁ (aggregate+ (credStake ∪ ptrStake ∪ rewards))
--
--   We can apply meaning preserving operations to get equivalent expressions
--
--   (dom activeDelegs) ◁ (aggregate+ (credStake ∪ ptrStake ∪ rewards))
--   aggregate+ (dom activeDelegs ◁ (credStake ∪ ptrStake ∪ rewards))
--   aggregate+ ((dom activeDelegs ◁ credStake) ∪ (dom activeDelegs ◁ ptrStake) ∪ (dom activeDelegs ◁ rewards))
--
--   We will compute this in several steps
--   step1 = (dom activeDelegs ◁ credStake) ∪ (dom activeDelegs ◁ ptrStake)
--   step2 =  aggregate (dom activeDelegs ◁ rewards) step1
--   This function has a non-incremental analog, 'stakeDistr', mosty used in tests, which does use the UTxO.
incrementalStakeDistr ::
  forall crypto.
  IncrementalStake crypto ->
  DState crypto ->
  PState crypto ->
  SnapShot crypto
incrementalStakeDistr incstake ds ps =
  SnapShot
    (Stake $ VMap.fromMap (compactCoinOrError <$> step2))
    delegs
    (VMap.fromMap poolParams)
  where
    UnifiedMap tripmap ptrmap = _unified ds
    PState poolParams _ _ = ps
    delegs = UM.viewToVMap (delegations ds)
    -- A credential is active, only if it is being delegated
    step1 = resolveActiveIncrementalPtrs (`VMap.member` delegs) ptrmap incstake
    step2 = aggregateActiveStake tripmap step1

-- | Resolve inserts and deletes which were indexed by Ptrs, by looking them
--   up in 'ptrs' and combining the result of the lookup with the ordinary stake.
--   keep ony the active credentials.
--   This is  step1 = (dom activeDelegs ◁ credStake) ∪ (dom activeDelegs ◁ ptrStake)
resolveActiveIncrementalPtrs ::
  (Credential 'Staking crypto -> Bool) ->
  Map Ptr (Credential 'Staking crypto) ->
  IncrementalStake crypto ->
  Map (Credential 'Staking crypto) Coin
resolveActiveIncrementalPtrs isActive ptrMap (IStake credStake ptrStake) =
  Map.foldlWithKey' accum step1A ptrStake -- step1A  ∪ (dom activeDelegs ◁ ptrStake)
  where
    -- (dom activeDelegs ◁ credStake)
    step1A = Map.filterWithKey (\k _ -> isActive k) credStake
    accum ans ptr coin =
      case Map.lookup ptr ptrMap of -- Map ptrs to Credentials
        Nothing -> ans
        Just cred ->
          if isActive cred
            then Map.insertWith (<>) cred coin ans
            else ans

-- | Aggregate active stake by merging two maps. The triple map from the
--   UnifiedMap, and the IncrementalStake Only keep the active stake. Active can
--   be determined if there is a (SJust deleg) in the Triple.  This is step2 =
--   aggregate (dom activeDelegs ◁ rewards) step1
aggregateActiveStake :: Ord k => Map k (Triple crypto) -> Map k Coin -> Map k Coin
aggregateActiveStake tripmap incremental =
  Map.mergeWithKey
    -- How to merge the ranges of the two maps where they have a common key. Below
    -- 'coin1' and 'coin2' have the same key, '_k', and the stake is active if the delegation is SJust
    (\_k trip coin2 -> (<> coin2) <$> UM.tripRewardActiveDelegation trip)
    -- what to do when a key appears just in 'tripmap', we only add the coin if the key is active
    (Map.mapMaybe UM.tripRewardActiveDelegation)
    -- what to do when a key is only in 'incremental', keep everything, because at
    -- the call site of aggregateActiveStake, the arg 'incremental' is filtered by
    -- 'resolveActiveIncrementalPtrs' which guarantees that only active stake is included.
    id
    tripmap
    incremental

-- ================================================

-- | A valid (or self-consistent) UTxOState{_utxo, _deposited, _fees, _ppups, _stakeDistro}
--   maintains an invariant between the _utxo and _stakeDistro fields. the _stakeDistro field is
--   the aggregation of Coin over the StakeReferences in the UTxO. It can be computed by a pure
--   function from the _utxo field. In some situations, mostly unit or example tests, or when
--   initializing a small UTxO, we want to create a UTxOState that computes the _stakeDistro from
--   the _utxo. This is aways safe to do, but if the _utxo field is big, this can be very expensive,
--   which defeats the purpose of memoizing the _stakeDistro field. So use of this function should be
--   restricted to tests and initializations, where the invariant should be maintained.
smartUTxOState ::
  ( Era era
  ) =>
  UTxO era ->
  Coin ->
  Coin ->
  State (Core.EraRule "PPUP" era) ->
  UTxOState era
smartUTxOState utxo c1 c2 st =
  UTxOState
    utxo
    c1
    c2
    st
    (updateStakeDistribution mempty mempty utxo)

-- ==============================

-- | Apply a reward update
applyRUpd ::
  ( HasField "_protocolVersion" (Core.PParams era) ProtVer
  ) =>
  RewardUpdate (Crypto era) ->
  EpochState era ->
  EpochState era
applyRUpd ru es =
  let (es', _, _, _) = applyRUpd' ru es
   in es'

applyRUpd' ::
  ( HasField "_protocolVersion" (Core.PParams era) ProtVer
  ) =>
  RewardUpdate (Crypto era) ->
  EpochState era ->
  ( EpochState era,
    Map (Credential 'Staking (Crypto era)) (Set (Reward (Crypto era))),
    Map (Credential 'Staking (Crypto era)) (Set (Reward (Crypto era))),
    Set (Credential 'Staking (Crypto era))
  )
applyRUpd'
  ru
  es@(EpochState as ss ls pr pp _nm) =
    (EpochState as' ss ls' pr pp nm', registered, eraIgnored, unregistered)
    where
      utxoState_ = lsUTxOState ls
      delegState = lsDPState ls
      dState = dpsDState delegState
      (registered, eraIgnored, unregistered, totalUnregistered) =
        filterAllRewards (rs ru) es
      registeredAggregated = aggregateRewards pp registered
      as' =
        as
          { _treasury = addDeltaCoin (_treasury as) (deltaT ru) <> totalUnregistered,
            _reserves = addDeltaCoin (_reserves as) (deltaR ru)
          }
      ls' =
        ls
          { lsUTxOState =
              utxoState_ {_fees = _fees utxoState_ `addDeltaCoin` deltaF ru},
            lsDPState =
              delegState
                { dpsDState =
                    dState
                      { _unified = (rewards dState UM.∪+ registeredAggregated)
                      }
                }
          }
      nm' = nonMyopic ru

filterAllRewards ::
  ( HasField "_protocolVersion" (Core.PParams era) ProtVer
  ) =>
  Map (Credential 'Staking (Crypto era)) (Set (Reward (Crypto era))) ->
  EpochState era ->
  ( Map (Credential 'Staking (Crypto era)) (Set (Reward (Crypto era))),
    Map (Credential 'Staking (Crypto era)) (Set (Reward (Crypto era))),
    Set (Credential 'Staking (Crypto era)),
    Coin
  )
filterAllRewards rs' (EpochState _as _ss ls pr _pp _nm) =
  (registered, eraIgnored, unregistered, totalUnregistered)
  where
    delegState = lsDPState ls
    dState = dpsDState delegState
    (regRU, unregRU) =
      Map.partitionWithKey
        (\k _ -> eval (k ∈ dom (rewards dState)))
        rs'
    totalUnregistered = fold $ aggregateRewards pr unregRU
    unregistered = Map.keysSet unregRU
    (registered, eraIgnored) = filterRewards pr regRU

decayFactor :: Float
decayFactor = 0.9

updateNonMyopic ::
  NonMyopic crypto ->
  Coin ->
  Map (KeyHash 'StakePool crypto) Likelihood ->
  NonMyopic crypto
updateNonMyopic nm rPot newLikelihoods =
  nm
    { likelihoodsNM = updatedLikelihoods,
      rewardPotNM = rPot
    }
  where
    history = likelihoodsNM nm
    performance kh newPerf =
      maybe
        mempty
        (applyDecay decayFactor)
        (Map.lookup kh history)
        <> newPerf
    updatedLikelihoods = Map.mapWithKey performance newLikelihoods

-- =============================
-- To prevent a huge pause, at the stability point, we spread out the
-- Calculation of rewards over many blocks. We do this in 3 phases. Phase 1
-- of a reward upate is a pure computation, computing some parameters which
-- become fixed at the time when we reach the stability point. One of these
-- parameters is a Pulser, i.e. a computation that when pulseM'ed computes
-- a portion of what is required, so that the whole compuation can be spread out in time.

-- | The EpochState has a field which is (Core.PParams era). We need these
--     fields, a subset of the fields in PParams, in: startStep and createRUpd.
type UsesPP era =
  ( HasField "_d" (Core.PParams era) UnitInterval,
    HasField "_tau" (Core.PParams era) UnitInterval,
    HasField "_a0" (Core.PParams era) NonNegativeInterval,
    HasField "_rho" (Core.PParams era) UnitInterval,
    HasField "_nOpt" (Core.PParams era) Natural,
    HasField "_protocolVersion" (Core.PParams era) ProtVer
  )

-- | Assemble the components for, and then create, a Pulser.
startStep ::
  forall era.
  UsesPP era =>
  EpochSize ->
  BlocksMade (Crypto era) ->
  EpochState era ->
  Coin ->
  ActiveSlotCoeff ->
  Word64 ->
  (PulsingRewUpdate (Crypto era), RewardProvenance (Crypto era))
startStep slotsPerEpoch b@(BlocksMade b') es@(EpochState acnt ss ls pr _ nm) maxSupply asc secparam =
  let SnapShot stake' delegs' poolParams = _pstakeGo ss
      numStakeCreds, k :: Rational
      numStakeCreds = fromIntegral (VMap.size $ unStake stake')
      k = fromIntegral secparam

      -- We expect approximately 10k-many blocks to be produced each epoch.
      -- The reward calculation begins (4k/f)-many slots into the epoch,
      -- and we guarantee that it ends (2k/f)-many slots before the end
      -- of the epoch (to allow tools such as db-sync to see the reward
      -- values in advance of them being applied to the ledger state).
      --
      -- Therefore to evenly space out the reward calculation, we divide
      -- the number of stake credentials by 4k in order to determine how many
      -- stake credential rewards we should calculate each block.
      -- If it does not finish in this amount of time, the calculation is
      -- forced to completion.
      pulseSize = max 1 (ceiling (numStakeCreds / (4 * k)))

      -- We now compute the amount of total rewards that can potentially be given
      -- out this epoch, and the adjustments to the reserves and the treasury.
      Coin reserves = _reserves acnt
      ds = dpsDState $ lsDPState ls
      -- reserves and rewards change
      deltaR1 =
        rationalToCoinViaFloor $
          min 1 eta
            * unboundRational (getField @"_rho" pr)
            * fromIntegral reserves
      d = unboundRational (getField @"_d" pr)
      expectedBlocks =
        floor $
          (1 - d) * unboundRational (activeSlotVal asc) * fromIntegral slotsPerEpoch
      -- TODO asc is a global constant, and slotsPerEpoch should not change often at all,
      -- it would be nice to not have to compute expectedBlocks every epoch
      blocksMade = fromIntegral $ Map.foldr (+) 0 b' :: Integer
      eta
        | unboundRational (getField @"_d" pr) >= 0.8 = 1
        | otherwise = blocksMade % expectedBlocks
      Coin rPot = _feeSS ss <> deltaR1
      deltaT1 = floor $ unboundRational (getField @"_tau" pr) * fromIntegral rPot
      _R = Coin $ rPot - deltaT1

      -- We now compute stake pool specific values that are needed for computing
      -- member and leader rewards.
      activestake = sumAllStake stake'
      totalStake = circulation es maxSupply
      stakePerPool = sumStakePerPool delegs' stake'
      mkPoolRewardInfoCurry =
        mkPoolRewardInfo
          pr
          _R
          b
          (fromIntegral blocksMade)
          stake'
          delegs'
          stakePerPool
          totalStake
          activestake

      -- We map over the registered stake pools to compute the revelant
      -- stake pool specific values.
      allPoolInfo = VMap.map mkPoolRewardInfoCurry poolParams

      -- Stake pools that do not produce any blocks get no rewards,
      -- but some information is still needed from non-block-producing
      -- pools for the ranking algorithm used by the wallets.
      blockProducingPoolInfo = VMap.toMap $ VMap.mapMaybe rightToMaybe allPoolInfo

      getSigma = unStakeShare . poolRelativeStake
      makeLikelihoods = \case
        -- This pool produced no blocks this epoch
        Left (StakeShare sigma) ->
          likelihood
            0
            (leaderProbability asc sigma $ getField @"_d" pr)
            slotsPerEpoch
        -- This pool produced at least one block this epoch
        Right info ->
          likelihood
            (poolBlocks info)
            (leaderProbability asc (getSigma info) $ getField @"_d" pr)
            slotsPerEpoch
      newLikelihoods = VMap.toMap $ VMap.map makeLikelihoods allPoolInfo

      -- We now compute the leader rewards for each stake pool.
      collectLRs acc poolRI =
        let rewardAcnt = getRwdCred . _poolRAcnt . poolPs $ poolRI
            packageLeaderReward = Set.singleton . leaderRewardToGeneral . poolLeaderReward
         in if HardForks.forgoRewardPrefilter pr || rewardAcnt `UM.member` rewards ds
              then
                Map.insertWith
                  Set.union
                  rewardAcnt
                  (packageLeaderReward poolRI)
                  acc
              else acc

      -- The data in 'RewardSnapShot' will be used to finish up the reward calculation
      -- once all the member rewards are complete.
      rewsnap =
        RewardSnapShot
          { rewFees = _feeSS ss,
            rewprotocolVersion = getField @"_protocolVersion" pr,
            rewNonMyopic = nm,
            rewDeltaR1 = deltaR1,
            rewR = _R,
            rewDeltaT1 = Coin deltaT1,
            rewLikelihoods = newLikelihoods,
            rewLeaders = Map.foldl' collectLRs mempty blockProducingPoolInfo
          }

      -- The data in 'FreeVars' to supply individual stake pool members with
      -- the neccessary information to compute their individual rewards.
      free =
        FreeVars
          delegs'
          (UM.domain $ rewards ds)
          (unCoin totalStake)
          (getField @"_protocolVersion" pr)
          blockProducingPoolInfo
      pulser :: Pulser (Crypto era)
      pulser =
        RSLP
          pulseSize
          free
          (unStake stake')
          (RewardAns Map.empty Map.empty)
      provenance =
        def
          { spe = case slotsPerEpoch of EpochSize n -> n,
            blocks = b,
            blocksCount = blocksMade,
            maxLL = maxSupply,
            deltaR1 = deltaR1,
            RP.r = _R,
            RP.totalStake = totalStake,
            RP.activeStake = activestake,
            d = d,
            expBlocks = expectedBlocks,
            eta = eta,
            rPot = Coin rPot,
            deltaT1 = Coin deltaT1
            -- The reward provenance is in the process of being deprecated,
            -- some fields are not populated anymore, such as the pool provenance
            -- and the desireabilities.
          }
   in (Pulsing rewsnap pulser, provenance)

-- Phase 2

-- | Run the pulser for a bit. If is has nothing left to do, complete it.
pulseStep ::
  PulsingRewUpdate crypto ->
  ShelleyBase (PulsingRewUpdate crypto, RewardEvent crypto)
pulseStep (Complete r) = pure (Complete r, mempty)
pulseStep p@(Pulsing _ pulser) | done pulser = completeStep p
pulseStep (Pulsing rewsnap pulser) = do
  -- The pulser might compute provenance, but using pulseM here does not compute it
  p2@(RSLP _ _ _ (RewardAns _ event)) <- pulseM pulser
  pure (Pulsing rewsnap p2, event)

-- Phase 3

completeStep ::
  PulsingRewUpdate crypto ->
  ShelleyBase (PulsingRewUpdate crypto, RewardEvent crypto)
completeStep (Complete r) = pure (Complete r, mempty)
completeStep (Pulsing rewsnap pulser) = do
  (p2, !event) <- runProvM (completeRupd (Pulsing rewsnap pulser))
  pure (Complete p2, event)

-- | Phase 3 of reward update has several parts
--   a) completeM the pulser (in case there are still computions to run)
--   b) Combine the pulser provenance with the RewardProvenance
--   c) Construct the final RewardUpdate
--   d) Add the leader rewards to both the events and the computed Rewards
completeRupd ::
  PulsingRewUpdate crypto ->
  ProvM (RewardProvenance crypto) ShelleyBase (RewardUpdate crypto, RewardEvent crypto)
completeRupd (Complete x) = pure (x, mempty)
completeRupd
  ( Pulsing
      rewsnap@RewardSnapShot
        { rewDeltaR1 = deltaR1,
          rewFees = feesSS,
          rewR = oldr,
          rewDeltaT1 = (Coin deltaT1),
          rewNonMyopic = nm,
          rewLikelihoods = newLikelihoods,
          rewLeaders = lrewards
        }
      pulser@(RSLP _size _free _source (RewardAns prev _now)) -- If prev is Map.empty, we have never pulsed.
    ) = do
    RewardAns rs_ events <- lift (completeM pulser)
    let rs' = Map.map Set.singleton rs_
    let rs'' = Map.unionWith Set.union rs' lrewards
    let !events' = Map.unionWith Set.union events lrewards

    let deltaR2 = oldr <-> sumRewards rewsnap rs''
    modifyM (\rp -> rp {deltaR2 = deltaR2})
    let neverpulsed = Map.null prev
        !newevent =
          if neverpulsed -- If we have never pulsed then everything in the computed needs to added to the event
            then Map.unionWith Set.union rs' events'
            else events'
    pure
      ( RewardUpdate
          { deltaT = DeltaCoin deltaT1,
            deltaR = invert (toDeltaCoin deltaR1) <> toDeltaCoin deltaR2,
            rs = rs'',
            deltaF = invert (toDeltaCoin feesSS),
            nonMyopic = updateNonMyopic nm oldr newLikelihoods
          },
        newevent
      )

-- | To create a reward update, run all 3 phases
--   This function is not used in the rules, so it ignores RewardEvents
createRUpd ::
  forall era.
  (UsesPP era) =>
  EpochSize ->
  BlocksMade (Crypto era) ->
  EpochState era ->
  Coin ->
  ActiveSlotCoeff ->
  Word64 ->
  ProvM (RewardProvenance (Crypto era)) ShelleyBase (RewardUpdate (Crypto era))
createRUpd slotsPerEpoch blocksmade epstate maxSupply asc secparam = do
  let (step1, initialProvenance) = startStep slotsPerEpoch blocksmade epstate maxSupply asc secparam
  modifyM (\_ -> initialProvenance)
  (step2, _event) <- lift (pulseStep step1)
  case step2 of
    (Complete r) -> pure r
    (Pulsing rewsnap pulser) -> fst <$> completeRupd (Pulsing rewsnap pulser)

-- =====================================================================

-- | Calculate the current circulation
--
-- This is used in the rewards calculation, and for API endpoints for pool ranking.
circulation :: EpochState era -> Coin -> Coin
circulation (EpochState acnt _ _ _ _ _) supply =
  supply <-> _reserves acnt

-- | Update new epoch state
updateNES ::
  NewEpochState era ->
  BlocksMade (Crypto era) ->
  LedgerState era ->
  NewEpochState era
updateNES
  oldNes@( NewEpochState
             _eL
             _bprev
             _
             (EpochState acnt ss _ pr pp nm)
             _ru
             _pd
             _avvm
           )
  bcur
  ls =
    oldNes
      { nesBcur = bcur,
        nesEs = EpochState acnt ss ls pr pp nm
      }

returnRedeemAddrsToReserves ::
  forall era.
  Era era =>
  EpochState era ->
  EpochState era
returnRedeemAddrsToReserves es = es {esAccountState = acnt', esLState = ls'}
  where
    ls = esLState es
    us = lsUTxOState ls
    UTxO utxo = _utxo us
    (redeemers, nonredeemers) =
      SplitMap.partition (maybe False isBootstrapRedeemer . getTxOutBootstrapAddress) utxo
    acnt = esAccountState es
    utxoR = UTxO redeemers :: UTxO era
    acnt' =
      acnt
        { _reserves = _reserves acnt <+> Val.coin (balance utxoR)
        }
    us' = us {_utxo = UTxO nonredeemers :: UTxO era}
    ls' = ls {lsUTxOState = us'}

--------------------------------------------------------------------------------
-- Default instances
--------------------------------------------------------------------------------

instance Default (PPUPState era) where
  def = PPUPState emptyPPPUpdates emptyPPPUpdates

instance
  (Default (State (Core.EraRule "PPUP" era)), CC.Crypto (Crypto era)) =>
  Default (UTxOState era)
  where
  def = UTxOState mempty mempty mempty def mempty

instance
  (Default (LedgerState era), Default (Core.PParams era)) =>
  Default (EpochState era)
  where
  def = EpochState def def def def def def

instance Default (UTxOState era) => Default (LedgerState era) where
  def = LedgerState def def

instance Default (DPState crypto) where
  def = DPState def def

instance Default (InstantaneousRewards crypto) where
  def = InstantaneousRewards Map.empty Map.empty mempty mempty

instance Default (DState crypto) where
  def = emptyDState

emptyDState :: (DState crypto)
emptyDState =
  DState
    UM.empty
    Map.empty
    (GenDelegs Map.empty)
    def

instance Default (PState crypto) where
  def =
    PState Map.empty Map.empty Map.empty

instance Default AccountState where
  def = AccountState (Coin 0) (Coin 0)
