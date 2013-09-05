--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4421 and 4422.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4421, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4422, import this SQL file:
--
--     psql mediacloud < mediawords-4421-4422.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;

DROP TRIGGER story_sentences_last_updated_trigger ON story_sentences;

DROP FUNCTION story_sentences_last_updated_trigger();

ALTER TABLE stories
       ADD COLUMN last_updated timestamp with time zone NOT NULL DEFAULT now();
 
ALTER TABLE stories
       ALTER COLUMN last_updated DROP DEFAULT;

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4422;
    
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;
    
END;
$$
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION last_updated_trigger() RETURNS trigger AS
$$
   DECLARE
      path_change boolean;
   BEGIN
      -- RAISE NOTICE 'BEGIN ';                                                                                                                            

      IF ( TG_OP = 'UPDATE' ) OR (TG_OP = 'INSERT') then

      	 NEW.last_updated = now();

      END IF;

      RETURN NEW;
   END;
$$
LANGUAGE 'plpgsql';

CREATE INDEX stories_last_updated ON stories ( last_updated );

CREATE INDEX story_sentences_last_updated ON story_sentences ( last_updated );

CREATE TRIGGER stories_last_updated_trigger
	BEFORE INSERT OR UPDATE ON stories
	FOR EACH ROW
	EXECUTE PROCEDURE last_updated_trigger() ;

CREATE TRIGGER story_sentences_last_updated_trigger
	BEFORE INSERT OR UPDATE ON story_sentences
	FOR EACH ROW
	EXECUTE PROCEDURE last_updated_trigger() ;

--
-- 2 of 2. Reset the database version.
--
SELECT set_database_schema_version();
