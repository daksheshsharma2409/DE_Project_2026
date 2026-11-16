SET search_path TO netflix;

\copy plans FROM 'seed_data/plans.csv' WITH (FORMAT csv, HEADER true, NULL '')
\copy accounts FROM 'seed_data/accounts.csv' WITH (FORMAT csv, HEADER true, NULL '')
\copy profiles FROM 'seed_data/profiles.csv' WITH (FORMAT csv, HEADER true, NULL '')
\copy genres FROM 'seed_data/genres.csv' WITH (FORMAT csv, HEADER true, NULL '')
\copy titles FROM 'seed_data/titles.csv' WITH (FORMAT csv, HEADER true, NULL '')
\copy title_genres FROM 'seed_data/title_genres.csv' WITH (FORMAT csv, HEADER true, NULL '')
\copy episodes FROM 'seed_data/episodes.csv' WITH (FORMAT csv, HEADER true, NULL '')
\copy viewing_activity FROM 'seed_data/viewing_activity.csv' WITH (FORMAT csv, HEADER true, NULL '')
\copy ratings FROM 'seed_data/ratings.csv' WITH (FORMAT csv, HEADER true, NULL '')
\copy my_list FROM 'seed_data/my_list.csv' WITH (FORMAT csv, HEADER true, NULL '')
\copy invoices FROM 'seed_data/invoices.csv' WITH (FORMAT csv, HEADER true, NULL '')

ANALYZE;

SELECT 'plans' AS table_name, count(*) AS row_count FROM plans
UNION ALL SELECT 'accounts', count(*) FROM accounts
UNION ALL SELECT 'profiles', count(*) FROM profiles
UNION ALL SELECT 'genres', count(*) FROM genres
UNION ALL SELECT 'titles', count(*) FROM titles
UNION ALL SELECT 'title_genres', count(*) FROM title_genres
UNION ALL SELECT 'episodes', count(*) FROM episodes
UNION ALL SELECT 'viewing_activity', count(*) FROM viewing_activity
UNION ALL SELECT 'ratings', count(*) FROM ratings
UNION ALL SELECT 'my_list', count(*) FROM my_list
UNION ALL SELECT 'invoices', count(*) FROM invoices
ORDER BY table_name;

SELECT 'episode-title mismatch' AS integrity_check, count(*) AS violations
FROM viewing_activity v
JOIN episodes e ON e.episode_id = v.episode_id
WHERE e.title_id <> v.title_id
UNION ALL
SELECT 'series/movie episode mismatch', count(*)
FROM viewing_activity v
JOIN titles t ON t.title_id = v.title_id
WHERE (t.title_type = 'SERIES' AND v.episode_id IS NULL)
   OR (t.title_type = 'MOVIE' AND v.episode_id IS NOT NULL)
UNION ALL
SELECT 'profiles over account limit', count(*)
FROM (
    SELECT account_id
    FROM profiles
    GROUP BY account_id
    HAVING count(*) > 5
) over_limit
UNION ALL
SELECT 'viewing before title added', count(*)
FROM viewing_activity v
JOIN titles t ON t.title_id = v.title_id
WHERE v.started_at::date < t.added_on;
