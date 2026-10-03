# OpenCode Session Manager

Two lightweight Bash utilities to manage OpenCode chat sessions on Linux. They help you recover valuable conversation history from corrupted databases or move sessions between machines, and keep the database lean to prevent future problems.

Both scripts run on standard Linux environments with nothing more than bash and sqlite3. They deliberately avoid process substitution and other exotic shell features so they also work on restricted hosting.

## Updated : super.sh does import, clean and export for opencode version from <1.18 to 2.0 and up 3 in 1 

## export.sh

Purpose: safely extract specific chat sessions from an old or crashed OpenCode database and import them into a fresh one.

Use cases:

* Recovery: restore specific conversations after OpenCode crashes because of a bloated or corrupted database
* Migration: transfer important chat history from one machine to another, for example from a laptop to a server
* Archiving: preserve critical project discussions before performing a full database reset

How it works: the script lists all sessions from the source database, you pick one by number, and it copies only that session's metadata, messages, and content parts into the target database. Events, permissions, and credentials are intentionally left behind to avoid carrying over corruption.

Notes:

* You must set OLD_DB and NEW_DB paths at the top of the script to match your system
* OpenCode must be closed while the script runs

## clean.sh

Purpose: interactive cleanup of old or unnecessary sessions to keep the database small and responsive.

Use cases:

* Performance maintenance: prevent future crashes caused by a database growing too large
* Privacy: remove sensitive conversations you no longer need
* Organization: clear out dead sessions left behind by abandoned tests or failed experiments

How it works: the script shows a numbered list of all sessions with titles and dates. You can select a single number, a range like 1-5, or a comma separated list like 1,3,8. A strict confirmation step requires typing YES to proceed, so accidental deletions are unlikely.

Notes:

* The script assumes the standard OpenCode database location at ~/.local/share/opencode/opencode.db
* If your database lives elsewhere, update the DB variable at the top
* OpenCode must be closed while the script runs

## Installation

1. Clone the repository or download the two .sh files
2. Make them executable:

```bash
chmod +x export.sh clean.sh
```

3. Adjust the database paths in session-export.sh if needed. The delete script usually works out of the box.

## Safety

* Always close OpenCode before running either script, otherwise you risk database locks or data inconsistency
* Back up your opencode.db file before mass deletions, the scripts use safe SQL transactions but a backup never hurts
* The export script reports how many messages were copied, and the delete script requires explicit confirmation

## Compatibility

Linux

MIT
