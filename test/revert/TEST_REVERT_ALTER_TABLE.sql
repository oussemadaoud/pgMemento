-- TEST_REVERT_ALTER_TABLE.sql
--
-- Author:      Felix Kunde <felix-kunde@gmx.de>
--
--              This script is free software under the LGPL Version 3
--              See the GNU Lesser General Public License at
--              http://www.gnu.org/copyleft/lgpl.html
--              for more details.
-------------------------------------------------------------------------------
-- About:
-- Script that checks log tables when an INSERT event happens
-- (also for logging initial state with pgmemento.log_table_state)
-------------------------------------------------------------------------------
--
-- ChangeLog:
--
-- Version | Date       | Description                                    | Author
-- 0.1.0     2018-10-10   initial commit                                   FKun
--

-- get test number
SELECT nextval('pgmemento.test_seq') AS n \gset

\echo
\echo 'TEST ':n': pgMemento revert ALTER TABLE event'

\echo
\echo 'TEST ':n'.1: Revert RENAME TABLE event'
DO
$$
DECLARE
  test_transaction INTEGER;
BEGIN
  -- set session_info to query logged transaction later
  PERFORM set_config('pgmemento.session_info', '{"message":"Reverting rename table"}'::text, FALSE);

  -- get transaction_id of last rename table event
  PERFORM
    pgmemento.revert_transaction(transaction_id)
  FROM
    pgmemento.table_event_log
  WHERE
    op_id = 12;

  -- query for logged transaction
  SELECT
    id
  INTO
    test_transaction
  FROM
    pgmemento.transaction_log
  WHERE
    session_info @> '{"message":"Reverting rename table"}'::jsonb;

  ASSERT test_transaction IS NOT NULL, 'Error: Did not find test entry in transaction_log table!';

  -- save transaction_id for next tests
  PERFORM set_config('pgmemento.revert_rename_table_test', test_transaction::text, FALSE);

  -- query for logged table event
  ASSERT (
    SELECT EXISTS (
      SELECT
        id
      FROM
        pgmemento.table_event_log
      WHERE
        transaction_id = test_transaction
        AND op_id = 12
    )
  ), 'Error: Did not find test entry in table_event_log table!';
END;
$$
LANGUAGE plpgsql;


\echo
\echo 'TEST ':n'.2: Check entries audit_table_log'
DO
$$
DECLARE
  test_transaction INTEGER;
  tabid INTEGER;
  tabname TEXT;
  tid_range numrange;
BEGIN
  test_transaction := current_setting('pgmemento.revert_rename_table_test')::int;

  -- get old parameters of renamed table
  SELECT
    id,
    table_name
  INTO
    tabid,
    tabname
  FROM
    pgmemento.audit_table_log
  WHERE
    relid = 'public.test'::regclass::oid
    AND upper(txid_range) = test_transaction;

  -- save table log id for next test
  PERFORM set_config('pgmemento.revert_rename_table_test2', tabid::text, FALSE);

  ASSERT tabname = 'tests', 'Did not find table ''%'' in audit_table_log', tabname;

  -- get new parameters of renamed table
  SELECT
    id,
    table_name,
    txid_range
  INTO
    tabid,
    tabname,
    tid_range
  FROM
    pgmemento.audit_table_log
  WHERE
    relid = 'public.test'::regclass::oid
    AND lower(txid_range) = test_transaction;

  -- save table log id for next test
  PERFORM set_config('pgmemento.revert_rename_table_test3', tabid::text, FALSE);

  ASSERT tabname = 'test', 'Did not find table ''%'' in audit_table_log', tabname;
  ASSERT upper(tid_range) IS NULL, 'Error: Renamed table should still exist and upper boundary of transaction range should be NULL, % instead', upper(tid_range);
END;
$$
LANGUAGE plpgsql;


\echo
\echo 'TEST ':n'.3: Check entries audit_column_log'
DO
$$
DECLARE
  test_transaction INTEGER;
  colnames TEXT[];
  datatypes TEXT[];
  tid_ranges numrange[];
BEGIN
  test_transaction := current_setting('pgmemento.revert_rename_table_test')::int;

  -- get column information of renamed table
  SELECT
    array_agg(column_name ORDER BY id),
    array_agg(data_type ORDER BY id),
    array_agg(txid_range ORDER BY id)
  INTO
    colnames,
    datatypes,
    tid_ranges
  FROM
    pgmemento.audit_column_log
  WHERE
    (audit_table_id = current_setting('pgmemento.revert_rename_table_test2')::int
    OR audit_table_id = current_setting('pgmemento.revert_rename_table_test3')::int)
    AND (lower(txid_range) = test_transaction OR upper(txid_range) = test_transaction);

  ASSERT colnames[1] = colnames[4]
     AND colnames[2] = colnames[5]
     AND colnames[3] = colnames[6], 'Error: Column names of renamed table in audit_column_log are not identical.';
  ASSERT datatypes[1] = datatypes[4]
     AND datatypes[2] = datatypes[5]
     AND datatypes[3] = datatypes[6], 'Error: Data types of columns of renamed table in audit_column_log are not identical.';  
  ASSERT upper(tid_ranges[1]) = test_transaction
     AND upper(tid_ranges[2]) = test_transaction
     AND upper(tid_ranges[3]) = test_transaction
     AND upper(tid_ranges[1]) = lower(tid_ranges[4])
     AND upper(tid_ranges[2]) = lower(tid_ranges[5])
     AND upper(tid_ranges[3]) = lower(tid_ranges[6]), 'Error: Start and end transaction ids for columns do not match the id % of ALTER TABLE RENAME TABLE event', test_transaction;
END;
$$
LANGUAGE plpgsql;
