CREATE SCHEMA netflix;
SET search_path TO netflix;

CREATE TABLE plans (
    plan_id             INTEGER PRIMARY KEY,
    plan_name           VARCHAR(20) NOT NULL UNIQUE
        CHECK (plan_name IN ('MOBILE', 'BASIC', 'STANDARD', 'PREMIUM')),
    monthly_price_inr   NUMERIC(8, 2) NOT NULL CHECK (monthly_price_inr >= 0),
    max_streams         SMALLINT NOT NULL CHECK (max_streams BETWEEN 1 AND 4),
    max_resolution      VARCHAR(5) NOT NULL
        CHECK (max_resolution IN ('480p', '720p', '1080p', '4K')),
    has_ads             BOOLEAN NOT NULL
);

CREATE TABLE accounts (
    account_id          INTEGER PRIMARY KEY,
    email               VARCHAR(254) NOT NULL UNIQUE
        CHECK (email = lower(email)),
    phone               VARCHAR(20),
    country_code        CHAR(2) NOT NULL
        CHECK (country_code IN ('IN', 'SG', 'AE')),
    plan_id             INTEGER NOT NULL REFERENCES plans(plan_id) ON DELETE RESTRICT,
    signup_date         DATE NOT NULL,
    status              VARCHAR(10) NOT NULL
        CHECK (status IN ('ACTIVE', 'CANCELLED', 'ON_HOLD')),
    cancelled_on        DATE,
    next_billing_date   DATE,
    CONSTRAINT accounts_phone_country_unique UNIQUE (country_code, phone),
    CONSTRAINT accounts_phone_format CHECK (phone IS NULL OR phone ~ '^[0-9]{10}$'),
    CONSTRAINT accounts_cancellation_dates CHECK (
        (status = 'CANCELLED' AND cancelled_on IS NOT NULL AND next_billing_date IS NULL)
        OR
        (status IN ('ACTIVE', 'ON_HOLD') AND cancelled_on IS NULL AND next_billing_date IS NOT NULL)
    ),
    CONSTRAINT accounts_dates_valid CHECK (
        cancelled_on IS NULL OR signup_date <= cancelled_on
    )
);

CREATE TABLE profiles (
    profile_id          INTEGER PRIMARY KEY,
    account_id          INTEGER NOT NULL REFERENCES accounts(account_id) ON DELETE RESTRICT,
    profile_name        VARCHAR(50) NOT NULL,
    is_kids             BOOLEAN NOT NULL,
    maturity_limit      VARCHAR(5) NOT NULL
        CHECK (maturity_limit IN ('U', 'UA7', 'UA13', 'UA16', 'A')),
    language            VARCHAR(30) NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL,
    CONSTRAINT profiles_kids_limit CHECK (
        NOT is_kids OR maturity_limit IN ('U', 'UA7')
    )
);

CREATE TABLE genres (
    genre_id            INTEGER PRIMARY KEY,
    genre_name          VARCHAR(30) NOT NULL UNIQUE
);

CREATE TABLE titles (
    title_id            INTEGER PRIMARY KEY,
    title_type          VARCHAR(6) NOT NULL CHECK (title_type IN ('MOVIE', 'SERIES')),
    name                VARCHAR(200) NOT NULL,
    release_year        SMALLINT NOT NULL CHECK (release_year BETWEEN 1888 AND 2100),
    maturity_rating     VARCHAR(5) NOT NULL
        CHECK (maturity_rating IN ('U', 'UA7', 'UA13', 'UA16', 'A')),
    original_language   VARCHAR(30) NOT NULL,
    runtime_min         SMALLINT,
    is_netflix_original BOOLEAN NOT NULL,
    added_on            DATE NOT NULL,
    leaving_on          DATE,
    CONSTRAINT titles_runtime_by_type CHECK (
        (title_type = 'MOVIE' AND runtime_min IS NOT NULL AND runtime_min > 0)
        OR
        (title_type = 'SERIES' AND runtime_min IS NULL)
    ),
    CONSTRAINT titles_originals_do_not_leave CHECK (
        NOT is_netflix_original OR leaving_on IS NULL
    )
);

CREATE TABLE title_genres (
    title_id            INTEGER NOT NULL REFERENCES titles(title_id) ON DELETE CASCADE,
    genre_id            INTEGER NOT NULL REFERENCES genres(genre_id) ON DELETE CASCADE,
    PRIMARY KEY (title_id, genre_id)
);

CREATE TABLE episodes (
    episode_id          INTEGER PRIMARY KEY,
    title_id            INTEGER NOT NULL REFERENCES titles(title_id) ON DELETE RESTRICT,
    season_no           SMALLINT NOT NULL CHECK (season_no > 0),
    episode_no          SMALLINT NOT NULL CHECK (episode_no > 0),
    episode_title       VARCHAR(200) NOT NULL,
    runtime_min         SMALLINT NOT NULL CHECK (runtime_min > 0),
    release_date        DATE NOT NULL,
    CONSTRAINT episodes_position_unique UNIQUE (title_id, season_no, episode_no),
    CONSTRAINT episodes_title_pair_unique UNIQUE (episode_id, title_id)
);

CREATE TABLE viewing_activity (
    view_id                 INTEGER PRIMARY KEY,
    profile_id              INTEGER NOT NULL REFERENCES profiles(profile_id) ON DELETE RESTRICT,
    title_id                INTEGER NOT NULL REFERENCES titles(title_id) ON DELETE RESTRICT,
    episode_id              INTEGER,
    started_at              TIMESTAMPTZ NOT NULL,
    duration_watched_sec    INTEGER NOT NULL CHECK (duration_watched_sec > 0),
    device_type             VARCHAR(10) NOT NULL
        CHECK (device_type IN ('TV', 'MOBILE', 'TABLET', 'LAPTOP')),
    completed               BOOLEAN NOT NULL,
    CONSTRAINT viewing_episode_matches_title
        FOREIGN KEY (episode_id, title_id)
        REFERENCES episodes(episode_id, title_id) ON DELETE RESTRICT
);

CREATE TABLE ratings (
    profile_id          INTEGER NOT NULL REFERENCES profiles(profile_id) ON DELETE RESTRICT,
    title_id            INTEGER NOT NULL REFERENCES titles(title_id) ON DELETE RESTRICT,
    rating              VARCHAR(12) NOT NULL
        CHECK (rating IN ('THUMBS_DOWN', 'THUMBS_UP', 'LOVE')),
    rated_at            TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (profile_id, title_id)
);

CREATE TABLE my_list (
    profile_id          INTEGER NOT NULL REFERENCES profiles(profile_id) ON DELETE RESTRICT,
    title_id            INTEGER NOT NULL REFERENCES titles(title_id) ON DELETE RESTRICT,
    added_at            TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (profile_id, title_id)
);

CREATE TABLE invoices (
    invoice_id              INTEGER PRIMARY KEY,
    account_id              INTEGER NOT NULL REFERENCES accounts(account_id) ON DELETE RESTRICT,
    billing_period_start    DATE NOT NULL CHECK (EXTRACT(DAY FROM billing_period_start) = 1),
    amount_inr              NUMERIC(8, 2) NOT NULL CHECK (amount_inr >= 0),
    status                  VARCHAR(8) NOT NULL
        CHECK (status IN ('PAID', 'FAILED', 'REFUNDED')),
    paid_at                 TIMESTAMPTZ,
    CONSTRAINT invoices_account_period_unique UNIQUE (account_id, billing_period_start),
    CONSTRAINT invoices_payment_time_matches_status CHECK (
        (status = 'FAILED' AND paid_at IS NULL)
        OR
        (status IN ('PAID', 'REFUNDED') AND paid_at IS NOT NULL)
    )
);
