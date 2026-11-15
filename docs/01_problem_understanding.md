# Problem Understanding

The database supports a Netflix-style streaming service: subscriptions and billing, household profiles, a movie and series catalogue, and each profile's viewing and discovery activity. The goal is to rebuild a reliable PostgreSQL schema from the surviving CSV exports before measuring the supplied workload.

| Problem | Business need | Stakeholders | Performance class |
|---|---|---|---|
| P1 - Slow home-screen rows | Load Continue Watching, Top 10, My List, and genre rows quickly and consistently for each profile. | Members, profiles, personalization/UI | Customer-facing / real-time |
| P2 - Slow title pages, autoplay, and search | Find catalogue details, episodes, the next episode, and matching titles without delaying playback. | Members, playback/search, content team | Customer-facing / real-time |
| P3 - Slow sign-in and profile switching | Find an account regardless of email case and list its profiles promptly. | Members, identity/support | Customer-facing / real-time |
| P4 - Empty unwatched-episode report | Identify episodes that have no matching viewing record so content teams can assess engagement. | Content strategy | Reporting / analytics |
| P5 - Slow retries, on-hold accounts, billing, and dunning | Find failed payments and overdue accounts, then process monthly invoices and account holds reliably. | Payments and billing, members | Mixed: interactive operations / real-time lookups and batch billing / reporting |
| P6 - Kids safety and account sharing | Detect age-rating mismatches for kids profiles and accounts whose concurrent activity exceeds plan streams. | Kids profiles, parents, compliance/trust | Reporting / analytics and compliance monitoring |
| P7 - Slow analytics and 20x viewing growth | Support binge, completion, device, original-title, rating, and My List reports as activity volume grows. | Content analytics, content strategy, marketing | Reporting / analytics |
| P8 - Revenue, churn, and support activity | Summarize plan revenue and cancellations, and let support inspect a member's recent activity. | Finance, support, members | Mixed: reports / analytics and an interactive support console |

## Assumptions

- The CSV exports define the initial data model and must load without changing their headers or rows.
- PostgreSQL is the target database. Query results and ordering in `queries/workload_30.sql` must remain unchanged.
- A household account owns its subscription and one or more profiles. Profiles own viewing activity, ratings, and My List entries.
- A non-null `episode_id` identifies a series episode. A null episode on a viewing row is a movie play.
- `completed` is an observed playback outcome, not a value that can be reconstructed reliably from watch duration.
- Invoice amount records the amount charged for that billing period; it is not guaranteed to equal the account's current plan price.
- Historical viewing and invoice records should not disappear as a side effect of deleting parent catalogue or account records.
- Performance tuning indexes are out of scope for this checkpoint. PostgreSQL's indexes created for primary-key and unique constraints are expected.
