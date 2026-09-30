-- Disposable PostgreSQL only; synthetic archived/current population records.
-- This explicitly demonstrates why archived-source equality is NOT permission to delete Cloud FK anchors.
BEGIN;
CREATE SCHEMA phase4_archive_fixture;
CREATE TABLE phase4_archive_fixture.houses(
  id text PRIMARY KEY, archived boolean NOT NULL
);
CREATE TABLE phase4_archive_fixture.people(
  id text PRIMARY KEY, house_id text NOT NULL REFERENCES phase4_archive_fixture.houses(id) ON DELETE RESTRICT,
  archived boolean NOT NULL
);
CREATE TABLE phase4_archive_fixture.clinical_history(
  id text PRIMARY KEY, person_id text NOT NULL REFERENCES phase4_archive_fixture.people(id) ON DELETE CASCADE
);
CREATE TABLE phase4_archive_fixture.residence_history(
  id text PRIMARY KEY, person_id text NOT NULL REFERENCES phase4_archive_fixture.people(id) ON DELETE RESTRICT
);
INSERT INTO phase4_archive_fixture.houses VALUES ('current-house',false),('retired-house',true);
INSERT INTO phase4_archive_fixture.people VALUES
  ('current-person','current-house',false),
  ('retired-protected-person','retired-house',true),
  ('retired-cascade-person','retired-house',true);
INSERT INTO phase4_archive_fixture.clinical_history VALUES
 ('protected-clinical','retired-protected-person'),
 ('cascade-clinical','retired-cascade-person');
INSERT INTO phase4_archive_fixture.residence_history VALUES
 ('protected-residence','retired-protected-person');
DO $test$ BEGIN
  IF (SELECT count(*) FROM phase4_archive_fixture.houses WHERE NOT archived) <> 1
     OR (SELECT count(*) FROM phase4_archive_fixture.people WHERE NOT archived) <> 1 THEN
    RAISE EXCEPTION 'Synthetic current-only projection did not exclude archived items';
  END IF;
  BEGIN
    DELETE FROM phase4_archive_fixture.people WHERE id='retired-protected-person';
    RAISE EXCEPTION 'BLOCKED: protected archived person unexpectedly deleted';
  EXCEPTION WHEN foreign_key_violation THEN NULL;
  END;
  BEGIN
    DELETE FROM phase4_archive_fixture.houses WHERE id='retired-house';
    RAISE EXCEPTION 'BLOCKED: retired FK-referenced house unexpectedly deleted';
  EXCEPTION WHEN foreign_key_violation THEN NULL;
  END;
  IF (SELECT count(*) FROM phase4_archive_fixture.clinical_history) <> 2
     OR (SELECT count(*) FROM phase4_archive_fixture.residence_history) <> 1 THEN
    RAISE EXCEPTION 'Archive-FK checks affected existing clinical/residence history';
  END IF;
END $test$;
-- Demonstrate a DIFFERENT dangerous case: a clinical record may disappear by CASCADE,
-- even if a separate Local encrypted archive exists. This occurs only inside a ROLLBACK fixture.
DELETE FROM phase4_archive_fixture.people WHERE id='retired-cascade-person';
DO $test$ BEGIN
  IF EXISTS (SELECT 1 FROM phase4_archive_fixture.clinical_history WHERE id='cascade-clinical') THEN
    RAISE EXCEPTION 'Synthetic cascade hazard was not reproduced';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM phase4_archive_fixture.people WHERE id='retired-protected-person') THEN
    RAISE EXCEPTION 'Archived protected reference was lost';
  END IF;
END $test$;
ROLLBACK;
SELECT 'PASS: synthetic FK RESTRICT/CASCADE archive hazards confirmed with full rollback; Cloud delete remains forbidden' AS result;
