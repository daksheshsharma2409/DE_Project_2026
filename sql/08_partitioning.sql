SET search_path TO netflix;

BEGIN;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'netflix'
          AND c.relname = 'viewing_activity'
          AND c.relkind = 'p'
    ) THEN
        RAISE EXCEPTION 'viewing_activity is already partitioned';
    END IF;
END $$;

ALTER TABLE viewing_activity RENAME TO viewing_activity_unpartitioned;

CREATE TABLE viewing_activity (
    view_id                 INTEGER NOT NULL,
    profile_id              INTEGER NOT NULL REFERENCES profiles(profile_id) ON DELETE RESTRICT,
    title_id                INTEGER NOT NULL REFERENCES titles(title_id) ON DELETE RESTRICT,
    episode_id              INTEGER,
    started_at              TIMESTAMPTZ NOT NULL,
    duration_watched_sec    INTEGER NOT NULL CHECK (duration_watched_sec > 0),
    device_type             VARCHAR(10) NOT NULL
        CHECK (device_type IN ('TV', 'MOBILE', 'TABLET', 'LAPTOP')),
    completed               BOOLEAN NOT NULL,
    PRIMARY KEY (view_id, started_at),
    CONSTRAINT viewing_episode_matches_title
        FOREIGN KEY (episode_id, title_id)
        REFERENCES episodes(episode_id, title_id) ON DELETE RESTRICT
) PARTITION BY RANGE (started_at);

CREATE TABLE viewing_activity_2025_01 PARTITION OF viewing_activity
    FOR VALUES FROM ('2025-01-01 00:00:00+05:30') TO ('2025-02-01 00:00:00+05:30');
CREATE TABLE viewing_activity_2025_02 PARTITION OF viewing_activity
    FOR VALUES FROM ('2025-02-01 00:00:00+05:30') TO ('2025-03-01 00:00:00+05:30');
CREATE TABLE viewing_activity_2025_03 PARTITION OF viewing_activity
    FOR VALUES FROM ('2025-03-01 00:00:00+05:30') TO ('2025-04-01 00:00:00+05:30');
CREATE TABLE viewing_activity_2025_04 PARTITION OF viewing_activity
    FOR VALUES FROM ('2025-04-01 00:00:00+05:30') TO ('2025-05-01 00:00:00+05:30');
CREATE TABLE viewing_activity_2025_05 PARTITION OF viewing_activity
    FOR VALUES FROM ('2025-05-01 00:00:00+05:30') TO ('2025-06-01 00:00:00+05:30');
CREATE TABLE viewing_activity_2025_06 PARTITION OF viewing_activity
    FOR VALUES FROM ('2025-06-01 00:00:00+05:30') TO ('2025-07-01 00:00:00+05:30');
CREATE TABLE viewing_activity_2025_07 PARTITION OF viewing_activity
    FOR VALUES FROM ('2025-07-01 00:00:00+05:30') TO ('2025-08-01 00:00:00+05:30');
CREATE TABLE viewing_activity_2025_08 PARTITION OF viewing_activity
    FOR VALUES FROM ('2025-08-01 00:00:00+05:30') TO ('2025-09-01 00:00:00+05:30');
CREATE TABLE viewing_activity_2025_09 PARTITION OF viewing_activity
    FOR VALUES FROM ('2025-09-01 00:00:00+05:30') TO ('2025-10-01 00:00:00+05:30');
CREATE TABLE viewing_activity_2025_10 PARTITION OF viewing_activity
    FOR VALUES FROM ('2025-10-01 00:00:00+05:30') TO ('2025-11-01 00:00:00+05:30');
CREATE TABLE viewing_activity_2025_11 PARTITION OF viewing_activity
    FOR VALUES FROM ('2025-11-01 00:00:00+05:30') TO ('2025-12-01 00:00:00+05:30');
CREATE TABLE viewing_activity_2025_12 PARTITION OF viewing_activity
    FOR VALUES FROM ('2025-12-01 00:00:00+05:30') TO ('2026-01-01 00:00:00+05:30');
CREATE TABLE viewing_activity_2026_01 PARTITION OF viewing_activity
    FOR VALUES FROM ('2026-01-01 00:00:00+05:30') TO ('2026-02-01 00:00:00+05:30');
CREATE TABLE viewing_activity_2026_02 PARTITION OF viewing_activity
    FOR VALUES FROM ('2026-02-01 00:00:00+05:30') TO ('2026-03-01 00:00:00+05:30');
CREATE TABLE viewing_activity_2026_03 PARTITION OF viewing_activity
    FOR VALUES FROM ('2026-03-01 00:00:00+05:30') TO ('2026-04-01 00:00:00+05:30');
CREATE TABLE viewing_activity_2026_04 PARTITION OF viewing_activity
    FOR VALUES FROM ('2026-04-01 00:00:00+05:30') TO ('2026-05-01 00:00:00+05:30');
CREATE TABLE viewing_activity_2026_05 PARTITION OF viewing_activity
    FOR VALUES FROM ('2026-05-01 00:00:00+05:30') TO ('2026-06-01 00:00:00+05:30');
CREATE TABLE viewing_activity_2026_06 PARTITION OF viewing_activity
    FOR VALUES FROM ('2026-06-01 00:00:00+05:30') TO ('2026-07-01 00:00:00+05:30');
CREATE TABLE viewing_activity_2026_07 PARTITION OF viewing_activity
    FOR VALUES FROM ('2026-07-01 00:00:00+05:30') TO ('2026-08-01 00:00:00+05:30');

CREATE TABLE viewing_activity_default PARTITION OF viewing_activity DEFAULT;

INSERT INTO viewing_activity
SELECT * FROM viewing_activity_unpartitioned;

DO $$
BEGIN
    IF (SELECT count(*) FROM viewing_activity)
       <> (SELECT count(*) FROM viewing_activity_unpartitioned) THEN
        RAISE EXCEPTION 'partition copy row count mismatch';
    END IF;
END $$;

DROP TABLE viewing_activity_unpartitioned;

-- R01, R14, R16, FK: profile lookup, then DISTINCT ON order (title_id, started_at DESC).
CREATE INDEX viewing_profile_title_started_idx
    ON viewing_activity (profile_id, title_id, started_at DESC);

-- R03, R08, R09, R18, R23: started_at range/sort; INCLUDE makes R03/R09/R18 index-only.
CREATE INDEX viewing_started_idx
    ON viewing_activity (started_at)
    INCLUDE (title_id, profile_id, completed, device_type, duration_watched_sec);

-- R19, FK: per-title count/max without rescanning the whole activity table.
CREATE INDEX viewing_title_started_idx
    ON viewing_activity (title_id, started_at);

-- R13, FK: index only real episodes (episode_id IS NOT NULL).
CREATE INDEX viewing_episode_idx
    ON viewing_activity (episode_id)
    WHERE episode_id IS NOT NULL;

ANALYZE viewing_activity;

COMMIT;
