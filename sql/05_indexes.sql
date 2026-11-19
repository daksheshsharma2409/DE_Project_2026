SET search_path TO netflix;

-- R05: pg_trgm supports the trigram index below.
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- R01, R14, R16, FK: profile lookup, then DISTINCT ON order (title_id, started_at DESC).
CREATE INDEX viewing_profile_title_started_idx
    ON viewing_activity (profile_id, title_id, started_at DESC);

-- R03, R08, R09, R18, R23: started_at range/sort; INCLUDE makes R03/R09/R18 index-only.
CREATE INDEX viewing_started_idx
    ON viewing_activity (started_at)
    INCLUDE (title_id, profile_id, completed, device_type, duration_watched_sec);

-- R19, FK: per-title count/max without rescanning 200,401 rows.
CREATE INDEX viewing_title_started_idx
    ON viewing_activity (title_id, started_at);

-- R13, FK: index only real episodes (episode_id IS NOT NULL).
CREATE INDEX viewing_episode_idx
    ON viewing_activity (episode_id)
    WHERE episode_id IS NOT NULL;

-- R24, FK: one account's profiles in created_at order, index-only.
CREATE INDEX profiles_account_created_idx
    ON profiles (account_id, created_at)
    INCLUDE (profile_name, is_kids, maturity_limit);

-- R04, R25, FK: reverses the PK order for lookups by genre_id.
CREATE INDEX title_genres_genre_title_idx
    ON title_genres (genre_id, title_id);

-- R17, FK: lookup by title_id, with rating INCLUDEd.
CREATE INDEX ratings_title_idx
    ON ratings (title_id)
    INCLUDE (rating);

-- R20: added_at range, with title_id INCLUDEd.
CREATE INDEX my_list_added_idx
    ON my_list (added_at)
    INCLUDE (title_id);

-- R11, W05: only FAILED rows; period + account order, amount INCLUDEd.
CREATE INDEX invoices_failed_period_account_idx
    ON invoices (billing_period_start, account_id)
    INCLUDE (amount_inr)
    WHERE status = 'FAILED';

-- R10: matches the lower(email) expression used in WHERE.
CREATE INDEX accounts_lower_email_idx
    ON accounts (lower(email));

-- R12: only CANCELLED rows, by date, with signup_date INCLUDEd.
CREATE INDEX accounts_cancelled_on_idx
    ON accounts (cancelled_on)
    INCLUDE (signup_date)
    WHERE status = 'CANCELLED';

-- R21: only ON_HOLD rows, by billing date, with email INCLUDEd.
CREATE INDEX accounts_on_hold_billing_idx
    ON accounts (next_billing_date)
    INCLUDE (email)
    WHERE status = 'ON_HOLD';

-- R05: trigram GIN for the leading-wildcard ILIKE search.
CREATE INDEX titles_name_trgm_idx
    ON titles USING gin (name gin_trgm_ops);

-- R22: index only titles that have a leaving date.
CREATE INDEX titles_leaving_on_idx
    ON titles (leaving_on)
    WHERE leaving_on IS NOT NULL;

VACUUM (ANALYZE);
