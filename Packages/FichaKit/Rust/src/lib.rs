//! FSRS-6's arithmetic from fsrs-rs, Anki's FSRS library, as a C interface of
//! plain values for Ficha's Swift (ADR 0026): the next memory state and
//! interval for each rating, a memory state started from an SM-2 interval and
//! ease, retrievability, and the default parameters. Only what Ficha calls.
//!
//! Each function returns a status, and writes its result where its last
//! argument points only when the status is `Ok`. None keeps a pointer after it
//! returns, and each catches a panic, which never reaches Swift.

use std::panic::{self, UnwindSafe};

use fsrs::{FSRS, FSRSError, MemoryState};

/// How many parameters FSRS-6 has.
pub const FICHA_FSRS_PARAMETER_COUNT: usize = 21;

/// How a call went.
#[repr(C)]
#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum FichaFsrsStatus {
    /// It worked, and the result is where the last argument points.
    Ok,
    /// The parameters aren't finite numbers.
    InvalidParameters,
    /// A memory state, retention or number of days that fsrs-rs can't work
    /// with, which gave a result that isn't a finite number.
    InvalidInput,
    /// fsrs-rs failed in a way these functions don't expect.
    UnexpectedError,
    /// The last argument, where the result goes, is null.
    NullResult,
    /// fsrs-rs, or this crate, panicked: the call caught it.
    Panicked,
}

/// FSRS-6's parameters, in fsrs-rs's order.
#[repr(C)]
#[derive(Debug, PartialEq, Clone, Copy)]
pub struct FichaFsrsParameters {
    pub values: [f32; FICHA_FSRS_PARAMETER_COUNT],
}

/// A card's memory, as FSRS estimates it: its stability, in days, and its
/// difficulty, from 1 to 10.
#[repr(C)]
#[derive(Debug, PartialEq, Clone, Copy)]
pub struct FichaFsrsMemoryState {
    pub stability: f32,
    pub difficulty: f32,
}

/// A card's memory after a rating, and the interval FSRS gives it then for
/// the desired retention: in days, unrounded.
#[repr(C)]
#[derive(Debug, PartialEq, Clone, Copy)]
pub struct FichaFsrsNextState {
    pub memory_state: FichaFsrsMemoryState,
    pub interval: f32,
}

/// The next state for each of the four ratings.
#[repr(C)]
#[derive(Debug, PartialEq, Clone, Copy)]
pub struct FichaFsrsNextStates {
    pub again: FichaFsrsNextState,
    pub hard: FichaFsrsNextState,
    pub good: FichaFsrsNextState,
    pub easy: FichaFsrsNextState,
}

/// Writes FSRS-6's default parameters, fsrs-rs's `DEFAULT_PARAMETERS`.
///
/// # Safety
///
/// `result` is null, or points to memory for a `FichaFsrsParameters` that the
/// call may write.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ficha_fsrs_default_parameters(
    result: *mut FichaFsrsParameters,
) -> FichaFsrsStatus {
    // SAFETY: the caller's promise, which the function's documentation states.
    unsafe {
        catch_panic_and_write(result, || {
            Ok(FichaFsrsParameters {
                values: fsrs::DEFAULT_PARAMETERS,
            })
        })
    }
}

/// Writes the next memory state and interval for each rating, fsrs-rs's
/// `next_states`: from the card's memory state, or from none when
/// `has_memory_state` is false, for a new card, with the desired retention
/// and the whole days since the card's last review.
///
/// # Safety
///
/// `result` is null, or points to memory for a `FichaFsrsNextStates` that the
/// call may write.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ficha_fsrs_next_states(
    parameters: FichaFsrsParameters,
    has_memory_state: bool,
    memory_state: FichaFsrsMemoryState,
    desired_retention: f32,
    days_elapsed: u32,
    result: *mut FichaFsrsNextStates,
) -> FichaFsrsStatus {
    // SAFETY: the caller's promise, which the function's documentation states.
    unsafe {
        catch_panic_and_write(result, || {
            let fsrs = model(parameters)?;
            let current = has_memory_state.then_some(MemoryState::from(memory_state));
            let next = fsrs
                .next_states(current, desired_retention, days_elapsed)
                .map_err(status)?;
            Ok(FichaFsrsNextStates {
                again: next_state(next.again)?,
                hard: next_state(next.hard)?,
                good: next_state(next.good)?,
                easy: next_state(next.easy)?,
            })
        })
    }
}

/// Writes a memory state started from an SM-2 interval, in days, and ease,
/// such as 2.5, for a card whose reviews aren't known, at the retention SM-2
/// spaced it for: fsrs-rs's `memory_state_from_sm2`.
///
/// # Safety
///
/// `result` is null, or points to memory for a `FichaFsrsMemoryState` that
/// the call may write.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ficha_fsrs_memory_state_from_sm2(
    parameters: FichaFsrsParameters,
    ease: f32,
    interval: f32,
    sm2_retention: f32,
    result: *mut FichaFsrsMemoryState,
) -> FichaFsrsStatus {
    // SAFETY: the caller's promise, which the function's documentation states.
    unsafe {
        catch_panic_and_write(result, || {
            let memory_state = model(parameters)?
                .memory_state_from_sm2(ease, interval, sm2_retention)
                .map_err(status)?;
            Ok(FichaFsrsMemoryState::from(memory_state))
        })
    }
}

/// Writes the retrievability of a memory state after a number of days, which
/// can be a fraction of one, with the parameters' decay, as Anki reads it:
/// fsrs-rs's `current_retrievability`.
///
/// # Safety
///
/// `result` is null, or points to memory for a `float` that the call may
/// write.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ficha_fsrs_current_retrievability(
    parameters: FichaFsrsParameters,
    memory_state: FichaFsrsMemoryState,
    days_elapsed: f32,
    result: *mut f32,
) -> FichaFsrsStatus {
    // SAFETY: the caller's promise, which the function's documentation states.
    unsafe {
        catch_panic_and_write(result, || {
            let parameters = fsrs::check_and_fill_parameters(&parameters.values).map_err(status)?;
            let decay = parameters[FICHA_FSRS_PARAMETER_COUNT - 1];
            let retrievability =
                fsrs::current_retrievability(memory_state.into(), days_elapsed, decay);
            finite(retrievability)
        })
    }
}

/// Runs a function's work, catching a panic, and writes its result where
/// `result` points when it worked.
///
/// # Safety
///
/// `result` is null, or points to memory for a `T` that the call may write.
unsafe fn catch_panic_and_write<T>(
    result: *mut T,
    work: impl FnOnce() -> Result<T, FichaFsrsStatus> + UnwindSafe,
) -> FichaFsrsStatus {
    if result.is_null() {
        return FichaFsrsStatus::NullResult;
    }
    match panic::catch_unwind(work) {
        Ok(Ok(value)) => {
            // SAFETY: `result` isn't null, and the caller promised it points
            // to memory for a `T`.
            unsafe { result.write(value) };
            FichaFsrsStatus::Ok
        }
        Ok(Err(failure)) => failure,
        Err(_) => FichaFsrsStatus::Panicked,
    }
}

/// fsrs-rs's model with these parameters, which it checks and clips.
fn model(parameters: FichaFsrsParameters) -> Result<FSRS, FichaFsrsStatus> {
    FSRS::new(&parameters.values).map_err(status)
}

/// A next state whose memory state and interval are finite numbers.
fn next_state(state: fsrs::ItemState) -> Result<FichaFsrsNextState, FichaFsrsStatus> {
    Ok(FichaFsrsNextState {
        memory_state: state.memory.into(),
        interval: finite(state.interval)?,
    })
}

/// The number, unless it's infinite or not a number.
fn finite(number: f32) -> Result<f32, FichaFsrsStatus> {
    if number.is_finite() {
        Ok(number)
    } else {
        Err(FichaFsrsStatus::InvalidInput)
    }
}

/// The status for one of fsrs-rs's errors.
fn status(error: FSRSError) -> FichaFsrsStatus {
    match error {
        FSRSError::InvalidParameters => FichaFsrsStatus::InvalidParameters,
        FSRSError::InvalidInput => FichaFsrsStatus::InvalidInput,
        FSRSError::NotEnoughData
        | FSRSError::Interrupted
        | FSRSError::OptimalNotFound
        | FSRSError::InvalidDeckSize => FichaFsrsStatus::UnexpectedError,
    }
}

impl From<FichaFsrsMemoryState> for MemoryState {
    fn from(state: FichaFsrsMemoryState) -> Self {
        MemoryState {
            stability: state.stability,
            difficulty: state.difficulty,
        }
    }
}

impl From<MemoryState> for FichaFsrsMemoryState {
    fn from(state: MemoryState) -> Self {
        FichaFsrsMemoryState {
            stability: state.stability,
            difficulty: state.difficulty,
        }
    }
}
