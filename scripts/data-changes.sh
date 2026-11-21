#!/bin/bash
# Lists the commits since the last upload that changed the cards' data: the
# database and the scheduler. Since ADR 0030 those merge without waiting for
# Lucas, and they reach his cards only through an upload, so `make upload`
# runs this once the build is up, before it tags the build's commit
# `build-<number>`.
#
# scripts/data-changes.sh [<commit>]: compares with <commit>, by default the
# last upload's, the nearest build-* tag behind HEAD.

set -euo pipefail

# What reaches the cards' data, as git pathspecs from the repo's root, each
# with what it holds. One per line, so two branches that each add one change
# different lines: that layout is our own.
data_paths=(
  # The database schema and its migrations, which all live in FichaData/Schema*.
  'Packages/FichaKit/Sources/FichaData/Schema*'
  # The one way in to the cards that show up, those in Lucas's reviews, and
  # which cards take an answer.
  'Packages/FichaKit/Sources/FichaData/CardsInReviews.swift'
  # The scheduler, which spaces each review with FSRS, says where a card
  # stands: in Lucas's reviews, waiting in the inbox, buried, or set aside by
  # its deck or a deck it sits inside, and keeps the cards in his reviews for
  # the planners to pick from.
  'Packages/FichaKit/Sources/FichaCore/Scheduler/'
  # Which decks a deck sits inside, named as tags inside tags are (ADR 0021,
  # ADR 0024), which the scheduler reads to say a card is set aside by a deck
  # its deck sits inside, and to tell which cards are in a priority deck or a
  # deck inside one.
  'Packages/FichaKit/Sources/FichaCore/TagsInsideTags.swift'
  # Which cards review now brings, when the review panel shows up on its own
  # and with which cards, the settings' defaults, and the trigger's names,
  # which the review log stores.
  'Packages/FichaKit/Sources/FichaCore/ReviewNow.swift'
  'Packages/FichaKit/Sources/FichaCore/AppearancePlanner.swift'
  'Packages/FichaKit/Sources/FichaCore/ReviewSettings.swift'
  'Packages/FichaKit/Sources/FichaCore/Trigger.swift'
  # FSRS's arithmetic, which spaces every card, and its build (ADR 0026): our
  # crate, whole, with the version of fsrs-rs its lock pins, and the Swift that
  # wraps it for FichaCore.
  'Packages/FichaKit/Rust/'
  'Packages/FichaKit/Sources/FichaFSRS/'
)

since=${1:-$(git describe --tags --abbrev=0 --match 'build-*' HEAD 2>/dev/null || true)}
if [[ -z $since ]]; then
  echo "No earlier upload carries a build-* tag, so there's nothing to compare yet: from this upload on, each one's commit is tagged."
  exit 0
fi
changes=$(git log --format='  %h %s' "$since..HEAD" -- "${data_paths[@]}")
if [[ -z $changes ]]; then
  echo "Since $since, nothing changed the cards' database or scheduler."
else
  echo "Since $since, these changed the cards' database or scheduler. They reach Lucas's cards once he installs this build, so he looks at them first:"
  echo "$changes"
fi
