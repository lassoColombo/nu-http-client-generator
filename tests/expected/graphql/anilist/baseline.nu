# Auto-generated client for anilist v0.0.0
# Source: <spec>
# Auth: --token flag or $env.ANILIST_TOKEN

const BASE_URL = "https://example.com/graphql"
const DEFAULT_AUTH = "bearer"

# Build auth: returns {headers: record, query: string}
def build-auth [token?: string, auth_scheme?: string]: nothing -> record {
  let token_val = if ($token != null) and ($token | is-not-empty) { $token } else { $env | get -o ANILIST_TOKEN | default "" }
  let scheme = ($auth_scheme | default "bearer")
  if ($scheme == "none") or ($token_val | is-empty) { return {headers: {}, query: ""} }
  match $scheme {
    "none" => { {headers: {}, query: ""} }
    _ => { {headers: {Authorization: $"Bearer ($token_val)"}, query: ""} }
  }
}

# Serialize a single query parameter based on collection style
def serialize-qp [name: string, value: any, style: string]: nothing -> list<string> {
  if ($value == null) { return [] }
  let n = ($name | url encode)
  let is_list = ($value | describe | str starts-with "list")
  if ($value | describe | str starts-with "record") { return ($value | transpose k v | each { $"($n)[($in.k | into string | url encode)]=($in.v | into string | url encode)" }) }
  if not $is_list { return [$"($n)=($value | into string | url encode)"] }
  match $style {
    "multi" => { $value | each {|v| $"($n)=($v | into string | url encode)" } }
    "csv" => { let joined = ($value | each { $in | into string | url encode } | str join ","); [$"($n)=($joined)"] }
    "ssv" => { let joined = ($value | each { $in | into string | url encode } | str join "%20"); [$"($n)=($joined)"] }
    "tsv" => { let joined = ($value | each { $in | into string | url encode } | str join "%09"); [$"($n)=($joined)"] }
    "pipes" => { let joined = ($value | each { $in | into string | url encode } | str join "|"); [$"($n)=($joined)"] }
    "deepObject" => { $value | each {|v| $"($n)[]=($v | into string | url encode)" } }
    _ => { $value | each {|v| $"($n)=($v | into string | url encode)" } }
  }
}

# Build URL from base, path, and optional query string
def build-url [base: string, path: string, query?: string]: nothing -> string {
  let parsed = ($base | url parse | reject params)
  let full_path = if ($path | is-empty) { $parsed.path } else { [$parsed.path $path] | str join "/" | str replace --all --regex '/+' '/' }
  let result = ($parsed | upsert path $full_path)
  if ($query != null) and ($query | is-not-empty) { $result | upsert query $query | url join } else { $result | url join }
}

# Execute HTTP request with method dispatch
def do-request [method: string, url: string, auth: record, insecure: bool, raw: bool, dry_run: bool, max_time?: duration, allow_errors?: bool, content_type?: string, body?: any]: nothing -> any {
  let req_url = if ($auth.query | is-not-empty) { if ($url | str contains "?") { $"($url)&($auth.query)" } else { $"($url)?($auth.query)" } } else { $url }
  let timeout = ($max_time | default 30min)
  let ct = ($content_type | default "application/json")
  if $dry_run { return {method: $method, url: $req_url, headers: $auth.headers, query_string: $auth.query, content_type: $ct, timeout: $timeout, body: $body} }
  let resp = match $method {
    "get" => { http get --headers $auth.headers --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url }
    "head" => { http head --headers $auth.headers --max-time $timeout --insecure=$insecure $req_url }
    "options" => { http options --headers $auth.headers --max-time $timeout --insecure=$insecure $req_url }
    "post" => { http post --headers $auth.headers --content-type $ct --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url ($body | default {}) }
    "put" => { http put --headers $auth.headers --content-type $ct --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url ($body | default {}) }
    "patch" => { http patch --headers $auth.headers --content-type $ct --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url ($body | default {}) }
    "delete" => { if ($body | is-empty) { http delete --headers $auth.headers --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url } else { http delete --headers $auth.headers --content-type $ct --data $body --full --allow-errors --max-time $timeout --insecure=$insecure --raw=$raw $req_url } }
  }
  if ($method in ["head" "options"]) { return $resp }
  if $allow_errors { $resp } else if $resp.status == 204 { null } else if $resp.status >= 400 { error make --unspanned { msg: $"HTTP ($resp.status): ($resp.body)" } } else { $resp.body }
}

# Unwrap a GraphQL response: extract data.{field} and surface errors
def unwrap-graphql [resp: any, field: string] {
  if ($resp | describe) == "string" { return $resp }
  let errors = ($resp.errors? | default [])
  if ($errors | length) > 0 {
    let msgs = ($errors | each {|e| $e.message? | default "unknown error" } | str join "; ")
    error make --unspanned { msg: $"GraphQL error: ($msgs)" }
  }
  $resp.data? | get -o $field | default $resp.data?
}

def base-url-completer [] { ["https://example.com/graphql"] }
def auth-scheme-completer [] { ["bearer"] }

# Completers for enum parameters
def season-completer [] { ["FALL" "SPRING" "SUMMER" "WINTER"] }
def type-completer [] { ["ANIME" "MANGA"] }
def format-completer [] { ["MANGA" "MOVIE" "MUSIC" "NOVEL" "ONA" "ONE_SHOT" "OVA" "SPECIAL" "TV" "TV_SHORT"] }
def status-completer [] { ["CANCELLED" "FINISHED" "HIATUS" "NOT_YET_RELEASED" "RELEASING"] }
def source-completer [] { ["ANIME" "COMIC" "DOUJINSHI" "GAME" "LIGHT_NOVEL" "LIVE_ACTION" "MANGA" "MULTIMEDIA_PROJECT" "NOVEL" "ORIGINAL" "OTHER" "PICTURE_BOOK" "VIDEO_GAME" "VISUAL_NOVEL" "WEB_NOVEL"] }
def format-in-completer [] { ["MANGA" "MOVIE" "MUSIC" "NOVEL" "ONA" "ONE_SHOT" "OVA" "SPECIAL" "TV" "TV_SHORT"] }
def format-not-completer [] { ["MANGA" "MOVIE" "MUSIC" "NOVEL" "ONA" "ONE_SHOT" "OVA" "SPECIAL" "TV" "TV_SHORT"] }
def format-not-in-completer [] { ["MANGA" "MOVIE" "MUSIC" "NOVEL" "ONA" "ONE_SHOT" "OVA" "SPECIAL" "TV" "TV_SHORT"] }
def status-in-completer [] { ["CANCELLED" "FINISHED" "HIATUS" "NOT_YET_RELEASED" "RELEASING"] }
def status-not-completer [] { ["CANCELLED" "FINISHED" "HIATUS" "NOT_YET_RELEASED" "RELEASING"] }
def status-not-in-completer [] { ["CANCELLED" "FINISHED" "HIATUS" "NOT_YET_RELEASED" "RELEASING"] }
def source-in-completer [] { ["ANIME" "COMIC" "DOUJINSHI" "GAME" "LIGHT_NOVEL" "LIVE_ACTION" "MANGA" "MULTIMEDIA_PROJECT" "NOVEL" "ORIGINAL" "OTHER" "PICTURE_BOOK" "VIDEO_GAME" "VISUAL_NOVEL" "WEB_NOVEL"] }
def sort-completer [] { ["CHAPTERS" "CHAPTERS_DESC" "DURATION" "DURATION_DESC" "END_DATE" "END_DATE_DESC" "EPISODES" "EPISODES_DESC" "FAVOURITES" "FAVOURITES_DESC" "FORMAT" "FORMAT_DESC" "ID" "ID_DESC" "POPULARITY" "POPULARITY_DESC" "SCORE" "SCORE_DESC" "SEARCH_MATCH" "START_DATE" "START_DATE_DESC" "STATUS" "STATUS_DESC" "TITLE_ENGLISH" "TITLE_ENGLISH_DESC" "TITLE_NATIVE" "TITLE_NATIVE_DESC" "TITLE_ROMAJI" "TITLE_ROMAJI_DESC" "TRENDING" "TRENDING_DESC" "TYPE" "TYPE_DESC" "UPDATED_AT" "UPDATED_AT_DESC" "VOLUMES" "VOLUMES_DESC"] }
def sort-completer-1 [] { ["DATE" "DATE_DESC" "EPISODE" "EPISODE_DESC" "ID" "ID_DESC" "MEDIA_ID" "MEDIA_ID_DESC" "POPULARITY" "POPULARITY_DESC" "SCORE" "SCORE_DESC" "TRENDING" "TRENDING_DESC"] }
def sort-completer-2 [] { ["EPISODE" "EPISODE_DESC" "ID" "ID_DESC" "MEDIA_ID" "MEDIA_ID_DESC" "TIME" "TIME_DESC"] }
def sort-completer-3 [] { ["FAVOURITES" "FAVOURITES_DESC" "ID" "ID_DESC" "RELEVANCE" "ROLE" "ROLE_DESC" "SEARCH_MATCH"] }
def sort-completer-4 [] { ["FAVOURITES" "FAVOURITES_DESC" "ID" "ID_DESC" "LANGUAGE" "LANGUAGE_DESC" "RELEVANCE" "ROLE" "ROLE_DESC" "SEARCH_MATCH"] }
def status-completer-1 [] { ["COMPLETED" "CURRENT" "DROPPED" "PAUSED" "PLANNING" "REPEATING"] }
def status-in-completer-1 [] { ["COMPLETED" "CURRENT" "DROPPED" "PAUSED" "PLANNING" "REPEATING"] }
def status-not-in-completer-1 [] { ["COMPLETED" "CURRENT" "DROPPED" "PAUSED" "PLANNING" "REPEATING"] }
def status-not-completer-1 [] { ["COMPLETED" "CURRENT" "DROPPED" "PAUSED" "PLANNING" "REPEATING"] }
def sort-completer-5 [] { ["ADDED_TIME" "ADDED_TIME_DESC" "FINISHED_ON" "FINISHED_ON_DESC" "MEDIA_ID" "MEDIA_ID_DESC" "MEDIA_POPULARITY" "MEDIA_POPULARITY_DESC" "MEDIA_TITLE_ENGLISH" "MEDIA_TITLE_ENGLISH_DESC" "MEDIA_TITLE_NATIVE" "MEDIA_TITLE_NATIVE_DESC" "MEDIA_TITLE_ROMAJI" "MEDIA_TITLE_ROMAJI_DESC" "PRIORITY" "PRIORITY_DESC" "PROGRESS" "PROGRESS_DESC" "PROGRESS_VOLUMES" "PROGRESS_VOLUMES_DESC" "REPEAT" "REPEAT_DESC" "SCORE" "SCORE_DESC" "STARTED_ON" "STARTED_ON_DESC" "STATUS" "STATUS_DESC" "UPDATED_TIME" "UPDATED_TIME_DESC"] }
def sort-completer-6 [] { ["CHAPTERS_READ" "CHAPTERS_READ_DESC" "ID" "ID_DESC" "SEARCH_MATCH" "USERNAME" "USERNAME_DESC" "WATCHED_TIME" "WATCHED_TIME_DESC"] }
def type-completer-1 [] { ["ACTIVITY_LIKE" "ACTIVITY_MENTION" "ACTIVITY_MESSAGE" "ACTIVITY_REPLY" "ACTIVITY_REPLY_LIKE" "ACTIVITY_REPLY_SUBSCRIBED" "AIRING" "CHARACTER_SUBMISSION_UPDATE" "FOLLOWING" "MEDIA_DATA_CHANGE" "MEDIA_DELETION" "MEDIA_MERGE" "MEDIA_SUBMISSION_UPDATE" "RELATED_MEDIA_ADDITION" "STAFF_SUBMISSION_UPDATE" "THREAD_COMMENT_LIKE" "THREAD_COMMENT_MENTION" "THREAD_COMMENT_REPLY" "THREAD_LIKE" "THREAD_SUBSCRIBED"] }
def type-in-completer [] { ["ACTIVITY_LIKE" "ACTIVITY_MENTION" "ACTIVITY_MESSAGE" "ACTIVITY_REPLY" "ACTIVITY_REPLY_LIKE" "ACTIVITY_REPLY_SUBSCRIBED" "AIRING" "CHARACTER_SUBMISSION_UPDATE" "FOLLOWING" "MEDIA_DATA_CHANGE" "MEDIA_DELETION" "MEDIA_MERGE" "MEDIA_SUBMISSION_UPDATE" "RELATED_MEDIA_ADDITION" "STAFF_SUBMISSION_UPDATE" "THREAD_COMMENT_LIKE" "THREAD_COMMENT_MENTION" "THREAD_COMMENT_REPLY" "THREAD_LIKE" "THREAD_SUBSCRIBED"] }
def sort-completer-7 [] { ["FAVOURITES" "FAVOURITES_DESC" "ID" "ID_DESC" "NAME" "NAME_DESC" "SEARCH_MATCH"] }
def media-type-completer [] { ["ANIME" "MANGA"] }
def sort-completer-8 [] { ["CREATED_AT" "CREATED_AT_DESC" "ID" "ID_DESC" "RATING" "RATING_DESC" "SCORE" "SCORE_DESC" "UPDATED_AT" "UPDATED_AT_DESC"] }
def title-language-completer [] { ["ENGLISH" "ENGLISH_STYLISED" "NATIVE" "NATIVE_STYLISED" "ROMAJI" "ROMAJI_STYLISED"] }
def score-format-completer [] { ["POINT_10" "POINT_100" "POINT_10_DECIMAL" "POINT_3" "POINT_5"] }
def staff-name-language-completer [] { ["NATIVE" "ROMAJI" "ROMAJI_WESTERN"] }
def type-completer-2 [] { ["ACTIVITY" "ACTIVITY_REPLY" "THREAD" "THREAD_COMMENT"] }

# List all available API commands with their parameters
export def commands []: nothing -> table {
  let builtin_flags = ["base-url" "token" "auth-scheme" "insecure" "max-time" "raw" "allow-errors" "dry-run" "accept" "help"]
  let mod_name = (scope modules | where { $in.commands | any { $in.name == "query page" } } | get name | first)
  let mod_cmds = (scope modules | where name == $mod_name | get commands | first)
  let cmd_ids = ($mod_cmds | where name not-in [$mod_name "commands"] | get decl_id)
  scope commands | where decl_id in $cmd_ids | each {|cmd|
    let sig = $cmd.signatures | values | first
    let params = $sig
      | where parameter_type not-in ["input" "output"]
      | where parameter_name not-in $builtin_flags
      | select parameter_name parameter_type syntax_shape is_optional description
    let return_type = ($sig | where parameter_type == "output" | get -o syntax_shape | first | default "any")
    {
      name: ($cmd.name | str replace $"($mod_name) " "")
      description: $cmd.description
      extra_description: $cmd.extra_description
      return_type: $return_type
      params: $params
    }
  }
}

# GraphQL query: Page
#
# operationId: Page
export def "query page" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --page: int # The page number
  --per-page: int # The amount of entries per page, max 50
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"page": $page, "perPage": $per_page} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "__typename" }
    let body = {query: ("query($page: Int, $perPage: Int) { Page(page: $page, perPage: $perPage) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  }
  if $dry_run or $raw or $allow_errors { $result } else { unwrap-graphql $result "Page" }
}

# Media query
#
# operationId: Media
export def "query media" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --id: int # Filter by the media id
  --id-mal: int # Filter by the media's MyAnimeList id
  --start-date: string # Filter by the start date of the media
  --end-date: string # Filter by the end date of the media
  --season: string@season-completer # Filter by the season the media was released in
  --season-year: int # The year of the season (Winter 2017 would also include December 2016 releases). Requires season argument
  --type: string@type-completer # Filter by the media's type
  --format: string@format-completer # Filter by the media's format
  --status: string@status-completer # Filter by the media's current release status
  --episodes: int # Filter by amount of episodes the media has
  --duration: int # Filter by the media's episode length
  --chapters: int # Filter by the media's chapter count
  --volumes: int # Filter by the media's volume count
  --is-adult: oneof<nothing, bool> # Filter by if the media's intended for 18+ adult audiences
  --genre: string # Filter by the media's genres
  --tag: string # Filter by the media's tags
  --minimum-tag-rank: int # Only apply the tags filter argument to tags above this rank. Default: 18
  --tag-category: string # Filter by the media's tags with in a tag category
  --on-list: oneof<nothing, bool> # Filter by the media on the authenticated user's lists
  --licensed-by: string # Filter media by sites name with a online streaming or reading license
  --licensed-by-id: int # Filter media by sites id with a online streaming or reading license
  --average-score: int # Filter by the media's average score
  --popularity: int # Filter by the number of users with this media on their list
  --qp-source: string@source-completer # Filter by the source type of the media
  --country-of-origin: string # Filter by the media's country of origin
  --is-licensed: oneof<nothing, bool> # If the media is officially licensed or a self-published doujin release
  --search: string # Filter by search query
  --id-not: int # Filter by the media id
  --id-in: int # Filter by the media id (max 10,000 items)
  --id-not-in: int # Filter by the media id (max 10,000 items)
  --id-mal-not: int # Filter by the media's MyAnimeList id
  --id-mal-in: int # Filter by the media's MyAnimeList id (max 10,000 items)
  --id-mal-not-in: int # Filter by the media's MyAnimeList id (max 10,000 items)
  --start-date-greater: string # Filter by the start date of the media
  --start-date-lesser: string # Filter by the start date of the media
  --start-date-like: string # Filter by the start date of the media
  --end-date-greater: string # Filter by the end date of the media
  --end-date-lesser: string # Filter by the end date of the media
  --end-date-like: string # Filter by the end date of the media
  --format-in: string@format-in-completer # Filter by the media's format (max 10,000 items)
  --format-not: string@format-not-completer # Filter by the media's format
  --format-not-in: string@format-not-in-completer # Filter by the media's format (max 10,000 items)
  --status-in: string@status-in-completer # Filter by the media's current release status (max 10,000 items)
  --status-not: string@status-not-completer # Filter by the media's current release status
  --status-not-in: string@status-not-in-completer # Filter by the media's current release status (max 10,000 items)
  --episodes-greater: int # Filter by amount of episodes the media has
  --episodes-lesser: int # Filter by amount of episodes the media has
  --duration-greater: int # Filter by the media's episode length
  --duration-lesser: int # Filter by the media's episode length
  --chapters-greater: int # Filter by the media's chapter count
  --chapters-lesser: int # Filter by the media's chapter count
  --volumes-greater: int # Filter by the media's volume count
  --volumes-lesser: int # Filter by the media's volume count
  --genre-in: string # Filter by the media's genres (max 10,000 items)
  --genre-not-in: string # Filter by the media's genres (max 10,000 items)
  --tag-in: string # Filter by the media's tags (max 10,000 items)
  --tag-not-in: string # Filter by the media's tags (max 10,000 items)
  --tag-category-in: string # Filter by the media's tags with in a tag category (max 10,000 items)
  --tag-category-not-in: string # Filter by the media's tags with in a tag category (max 10,000 items)
  --licensed-by-in: string # Filter media by sites name with a online streaming or reading license (max 10,000 items)
  --licensed-by-id-in: int # Filter media by sites id with a online streaming or reading license (max 10,000 items)
  --average-score-not: int # Filter by the media's average score
  --average-score-greater: int # Filter by the media's average score
  --average-score-lesser: int # Filter by the media's average score
  --popularity-not: int # Filter by the number of users with this media on their list
  --popularity-greater: int # Filter by the number of users with this media on their list
  --popularity-lesser: int # Filter by the number of users with this media on their list
  --source-in: string@source-in-completer # Filter by the source type of the media (max 10,000 items)
  --qp-sort: string@sort-completer # The order the results will be returned in
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"id": $id, "idMal": $id_mal, "startDate": $start_date, "endDate": $end_date, "season": $season, "seasonYear": $season_year, "type": $type, "format": $format, "status": $status, "episodes": $episodes, "duration": $duration, "chapters": $chapters, "volumes": $volumes, "isAdult": $is_adult, "genre": $genre, "tag": $tag, "minimumTagRank": $minimum_tag_rank, "tagCategory": $tag_category, "onList": $on_list, "licensedBy": $licensed_by, "licensedById": $licensed_by_id, "averageScore": $average_score, "popularity": $popularity, "source": $qp_source, "countryOfOrigin": $country_of_origin, "isLicensed": $is_licensed, "search": $search, "id_not": $id_not, "id_in": $id_in, "id_not_in": $id_not_in, "idMal_not": $id_mal_not, "idMal_in": $id_mal_in, "idMal_not_in": $id_mal_not_in, "startDate_greater": $start_date_greater, "startDate_lesser": $start_date_lesser, "startDate_like": $start_date_like, "endDate_greater": $end_date_greater, "endDate_lesser": $end_date_lesser, "endDate_like": $end_date_like, "format_in": $format_in, "format_not": $format_not, "format_not_in": $format_not_in, "status_in": $status_in, "status_not": $status_not, "status_not_in": $status_not_in, "episodes_greater": $episodes_greater, "episodes_lesser": $episodes_lesser, "duration_greater": $duration_greater, "duration_lesser": $duration_lesser, "chapters_greater": $chapters_greater, "chapters_lesser": $chapters_lesser, "volumes_greater": $volumes_greater, "volumes_lesser": $volumes_lesser, "genre_in": $genre_in, "genre_not_in": $genre_not_in, "tag_in": $tag_in, "tag_not_in": $tag_not_in, "tagCategory_in": $tag_category_in, "tagCategory_not_in": $tag_category_not_in, "licensedBy_in": $licensed_by_in, "licensedById_in": $licensed_by_id_in, "averageScore_not": $average_score_not, "averageScore_greater": $average_score_greater, "averageScore_lesser": $average_score_lesser, "popularity_not": $popularity_not, "popularity_greater": $popularity_greater, "popularity_lesser": $popularity_lesser, "source_in": $source_in, "sort": $qp_sort} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "id idMal type format status description season seasonYear seasonInt episodes duration chapters volumes countryOfOrigin isLicensed source hashtag updatedAt bannerImage genres synonyms averageScore meanScore popularity isLocked trending favourites isFavourite isFavouriteBlocked isAdult siteUrl autoCreateForumThread isRecommendationBlocked isReviewBlocked modNotes" }
    let body = {query: ("query($id: Int, $idMal: Int, $startDate: FuzzyDateInt, $endDate: FuzzyDateInt, $season: MediaSeason, $seasonYear: Int, $type: MediaType, $format: MediaFormat, $status: MediaStatus, $episodes: Int, $duration: Int, $chapters: Int, $volumes: Int, $isAdult: Boolean, $genre: String, $tag: String, $minimumTagRank: Int, $tagCategory: String, $onList: Boolean, $licensedBy: String, $licensedById: Int, $averageScore: Int, $popularity: Int, $source: MediaSource, $countryOfOrigin: CountryCode, $isLicensed: Boolean, $search: String, $id_not: Int, $id_in: [Int], $id_not_in: [Int], $idMal_not: Int, $idMal_in: [Int], $idMal_not_in: [Int], $startDate_greater: FuzzyDateInt, $startDate_lesser: FuzzyDateInt, $startDate_like: String, $endDate_greater: FuzzyDateInt, $endDate_lesser: FuzzyDateInt, $endDate_like: String, $format_in: [MediaFormat], $format_not: MediaFormat, $format_not_in: [MediaFormat], $status_in: [MediaStatus], $status_not: MediaStatus, $status_not_in: [MediaStatus], $episodes_greater: Int, $episodes_lesser: Int, $duration_greater: Int, $duration_lesser: Int, $chapters_greater: Int, $chapters_lesser: Int, $volumes_greater: Int, $volumes_lesser: Int, $genre_in: [String], $genre_not_in: [String], $tag_in: [String], $tag_not_in: [String], $tagCategory_in: [String], $tagCategory_not_in: [String], $licensedBy_in: [String], $licensedById_in: [Int], $averageScore_not: Int, $averageScore_greater: Int, $averageScore_lesser: Int, $popularity_not: Int, $popularity_greater: Int, $popularity_lesser: Int, $source_in: [MediaSource], $sort: [MediaSort]) { Media(id: $id, idMal: $idMal, startDate: $startDate, endDate: $endDate, season: $season, seasonYear: $seasonYear, type: $type, format: $format, status: $status, episodes: $episodes, duration: $duration, chapters: $chapters, volumes: $volumes, isAdult: $isAdult, genre: $genre, tag: $tag, minimumTagRank: $minimumTagRank, tagCategory: $tagCategory, onList: $onList, licensedBy: $licensedBy, licensedById: $licensedById, averageScore: $averageScore, popularity: $popularity, source: $source, countryOfOrigin: $countryOfOrigin, isLicensed: $isLicensed, search: $search, id_not: $id_not, id_in: $id_in, id_not_in: $id_not_in, idMal_not: $idMal_not, idMal_in: $idMal_in, idMal_not_in: $idMal_not_in, startDate_greater: $startDate_greater, startDate_lesser: $startDate_lesser, startDate_like: $startDate_like, endDate_greater: $endDate_greater, endDate_lesser: $endDate_lesser, endDate_like: $endDate_like, format_in: $format_in, format_not: $format_not, format_not_in: $format_not_in, status_in: $status_in, status_not: $status_not, status_not_in: $status_not_in, episodes_greater: $episodes_greater, episodes_lesser: $episodes_lesser, duration_greater: $duration_greater, duration_lesser: $duration_lesser, chapters_greater: $chapters_greater, chapters_lesser: $chapters_lesser, volumes_greater: $volumes_greater, volumes_lesser: $volumes_lesser, genre_in: $genre_in, genre_not_in: $genre_not_in, tag_in: $tag_in, tag_not_in: $tag_not_in, tagCategory_in: $tagCategory_in, tagCategory_not_in: $tagCategory_not_in, licensedBy_in: $licensedBy_in, licensedById_in: $licensedById_in, averageScore_not: $averageScore_not, averageScore_greater: $averageScore_greater, averageScore_lesser: $averageScore_lesser, popularity_not: $popularity_not, popularity_greater: $popularity_greater, popularity_lesser: $popularity_lesser, source_in: $source_in, sort: $sort) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  }
  if $dry_run or $raw or $allow_errors { $result } else { unwrap-graphql $result "Media" }
}

# Media Trend query
#
# operationId: MediaTrend
export def "query media-trend" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --media-id: int # Filter by the media id
  --date: int # Filter by date
  --trending: int # Filter by trending amount
  --average-score: int # Filter by score
  --popularity: int # Filter by popularity
  --episode: int # Filter by episode number
  --releasing: oneof<nothing, bool> # Filter to stats recorded while the media was releasing
  --media-id-not: int # Filter by the media id
  --media-id-in: int # Filter by the media id (max 10,000 items)
  --media-id-not-in: int # Filter by the media id (max 10,000 items)
  --date-greater: int # Filter by date
  --date-lesser: int # Filter by date
  --trending-greater: int # Filter by trending amount
  --trending-lesser: int # Filter by trending amount
  --trending-not: int # Filter by trending amount
  --average-score-greater: int # Filter by score
  --average-score-lesser: int # Filter by score
  --average-score-not: int # Filter by score
  --popularity-greater: int # Filter by popularity
  --popularity-lesser: int # Filter by popularity
  --popularity-not: int # Filter by popularity
  --episode-greater: int # Filter by episode number
  --episode-lesser: int # Filter by episode number
  --episode-not: int # Filter by episode number
  --qp-sort: string@sort-completer-1 # The order the results will be returned in
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"mediaId": $media_id, "date": $date, "trending": $trending, "averageScore": $average_score, "popularity": $popularity, "episode": $episode, "releasing": $releasing, "mediaId_not": $media_id_not, "mediaId_in": $media_id_in, "mediaId_not_in": $media_id_not_in, "date_greater": $date_greater, "date_lesser": $date_lesser, "trending_greater": $trending_greater, "trending_lesser": $trending_lesser, "trending_not": $trending_not, "averageScore_greater": $average_score_greater, "averageScore_lesser": $average_score_lesser, "averageScore_not": $average_score_not, "popularity_greater": $popularity_greater, "popularity_lesser": $popularity_lesser, "popularity_not": $popularity_not, "episode_greater": $episode_greater, "episode_lesser": $episode_lesser, "episode_not": $episode_not, "sort": $qp_sort} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "mediaId date trending averageScore popularity inProgress releasing episode" }
    let body = {query: ("query($mediaId: Int, $date: Int, $trending: Int, $averageScore: Int, $popularity: Int, $episode: Int, $releasing: Boolean, $mediaId_not: Int, $mediaId_in: [Int], $mediaId_not_in: [Int], $date_greater: Int, $date_lesser: Int, $trending_greater: Int, $trending_lesser: Int, $trending_not: Int, $averageScore_greater: Int, $averageScore_lesser: Int, $averageScore_not: Int, $popularity_greater: Int, $popularity_lesser: Int, $popularity_not: Int, $episode_greater: Int, $episode_lesser: Int, $episode_not: Int, $sort: [MediaTrendSort]) { MediaTrend(mediaId: $mediaId, date: $date, trending: $trending, averageScore: $averageScore, popularity: $popularity, episode: $episode, releasing: $releasing, mediaId_not: $mediaId_not, mediaId_in: $mediaId_in, mediaId_not_in: $mediaId_not_in, date_greater: $date_greater, date_lesser: $date_lesser, trending_greater: $trending_greater, trending_lesser: $trending_lesser, trending_not: $trending_not, averageScore_greater: $averageScore_greater, averageScore_lesser: $averageScore_lesser, averageScore_not: $averageScore_not, popularity_greater: $popularity_greater, popularity_lesser: $popularity_lesser, popularity_not: $popularity_not, episode_greater: $episode_greater, episode_lesser: $episode_lesser, episode_not: $episode_not, sort: $sort) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  }
  if $dry_run or $raw or $allow_errors { $result } else { unwrap-graphql $result "MediaTrend" }
}

# Airing schedule query
#
# operationId: AiringSchedule
export def "query airing-schedule" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --id: int # Filter by the id of the airing schedule item
  --media-id: int # Filter by the id of associated media
  --episode: int # Filter by the airing episode number
  --airing-at: int # Filter by the time of airing
  --not-yet-aired: oneof<nothing, bool> # Filter to episodes that haven't yet aired
  --id-not: int # Filter by the id of the airing schedule item
  --id-in: int # Filter by the id of the airing schedule item (max 10,000 items)
  --id-not-in: int # Filter by the id of the airing schedule item (max 10,000 items)
  --media-id-not: int # Filter by the id of associated media
  --media-id-in: int # Filter by the id of associated media (max 10,000 items)
  --media-id-not-in: int # Filter by the id of associated media (max 10,000 items)
  --episode-not: int # Filter by the airing episode number
  --episode-in: int # Filter by the airing episode number (max 10,000 items)
  --episode-not-in: int # Filter by the airing episode number (max 10,000 items)
  --episode-greater: int # Filter by the airing episode number
  --episode-lesser: int # Filter by the airing episode number
  --airing-at-greater: int # Filter by the time of airing
  --airing-at-lesser: int # Filter by the time of airing
  --qp-sort: string@sort-completer-2 # The order the results will be returned in
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"id": $id, "mediaId": $media_id, "episode": $episode, "airingAt": $airing_at, "notYetAired": $not_yet_aired, "id_not": $id_not, "id_in": $id_in, "id_not_in": $id_not_in, "mediaId_not": $media_id_not, "mediaId_in": $media_id_in, "mediaId_not_in": $media_id_not_in, "episode_not": $episode_not, "episode_in": $episode_in, "episode_not_in": $episode_not_in, "episode_greater": $episode_greater, "episode_lesser": $episode_lesser, "airingAt_greater": $airing_at_greater, "airingAt_lesser": $airing_at_lesser, "sort": $qp_sort} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "id airingAt timeUntilAiring episode mediaId" }
    let body = {query: ("query($id: Int, $mediaId: Int, $episode: Int, $airingAt: Int, $notYetAired: Boolean, $id_not: Int, $id_in: [Int], $id_not_in: [Int], $mediaId_not: Int, $mediaId_in: [Int], $mediaId_not_in: [Int], $episode_not: Int, $episode_in: [Int], $episode_not_in: [Int], $episode_greater: Int, $episode_lesser: Int, $airingAt_greater: Int, $airingAt_lesser: Int, $sort: [AiringSort]) { AiringSchedule(id: $id, mediaId: $mediaId, episode: $episode, airingAt: $airingAt, notYetAired: $notYetAired, id_not: $id_not, id_in: $id_in, id_not_in: $id_not_in, mediaId_not: $mediaId_not, mediaId_in: $mediaId_in, mediaId_not_in: $mediaId_not_in, episode_not: $episode_not, episode_in: $episode_in, episode_not_in: $episode_not_in, episode_greater: $episode_greater, episode_lesser: $episode_lesser, airingAt_greater: $airingAt_greater, airingAt_lesser: $airingAt_lesser, sort: $sort) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  }
  if $dry_run or $raw or $allow_errors { $result } else { unwrap-graphql $result "AiringSchedule" }
}

# Character query
#
# operationId: Character
export def "query character" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --id: int # Filter by character id
  --is-birthday: oneof<nothing, bool> # Filter by character by if its their birthday today
  --search: string # Filter by search query
  --id-not: int # Filter by character id
  --id-in: int # Filter by character id (max 10,000 items)
  --id-not-in: int # Filter by character id (max 10,000 items)
  --qp-sort: string@sort-completer-3 # The order the results will be returned in
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"id": $id, "isBirthday": $is_birthday, "search": $search, "id_not": $id_not, "id_in": $id_in, "id_not_in": $id_not_in, "sort": $qp_sort} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "id description gender age bloodType isFavourite isFavouriteBlocked siteUrl updatedAt favourites modNotes" }
    let body = {query: ("query($id: Int, $isBirthday: Boolean, $search: String, $id_not: Int, $id_in: [Int], $id_not_in: [Int], $sort: [CharacterSort]) { Character(id: $id, isBirthday: $isBirthday, search: $search, id_not: $id_not, id_in: $id_in, id_not_in: $id_not_in, sort: $sort) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  }
  if $dry_run or $raw or $allow_errors { $result } else { unwrap-graphql $result "Character" }
}

# Staff query
#
# operationId: Staff
export def "query staff" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --id: int # Filter by the staff id
  --is-birthday: oneof<nothing, bool> # Filter by staff by if its their birthday today
  --search: string # Filter by search query
  --id-not: int # Filter by the staff id
  --id-in: int # Filter by the staff id (max 10,000 items)
  --id-not-in: int # Filter by the staff id (max 10,000 items)
  --qp-sort: string@sort-completer-4 # The order the results will be returned in
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"id": $id, "isBirthday": $is_birthday, "search": $search, "id_not": $id_not, "id_in": $id_in, "id_not_in": $id_not_in, "sort": $qp_sort} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "id language languageV2 description primaryOccupations gender age yearsActive homeTown bloodType isFavourite isFavouriteBlocked siteUrl updatedAt submissionStatus submissionNotes favourites modNotes" }
    let body = {query: ("query($id: Int, $isBirthday: Boolean, $search: String, $id_not: Int, $id_in: [Int], $id_not_in: [Int], $sort: [StaffSort]) { Staff(id: $id, isBirthday: $isBirthday, search: $search, id_not: $id_not, id_in: $id_in, id_not_in: $id_not_in, sort: $sort) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  }
  if $dry_run or $raw or $allow_errors { $result } else { unwrap-graphql $result "Staff" }
}

# Media list query
#
# operationId: MediaList
export def "query media-list" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --id: int # Filter by a list entry's id
  --user-id: int # Filter by a user's id
  --user-name: string # Filter by a user's name
  --type: string@type-completer # Filter by the list entries media type
  --status: string@status-completer-1 # Filter by the watching/reading status
  --media-id: int # Filter by the media id of the list entry
  --is-following: oneof<nothing, bool> # Filter list entries to users who are being followed by the authenticated user
  --notes: string # Filter by note words and #tags
  --started-at: string # Filter by the date the user started the media
  --completed-at: string # Filter by the date the user completed the media
  --compare-with-auth-list: oneof<nothing, bool> # Limit to only entries also on the auth user's list. Requires user id or name arguments.
  --user-id-in: int # Filter by a user's id (max 10,000 items)
  --status-in: string@status-in-completer-1 # Filter by the watching/reading status (max 10,000 items)
  --status-not-in: string@status-not-in-completer-1 # Filter by the watching/reading status (max 10,000 items)
  --status-not: string@status-not-completer-1 # Filter by the watching/reading status
  --media-id-in: int # Filter by the media id of the list entry (max 10,000 items)
  --media-id-not-in: int # Filter by the media id of the list entry (max 10,000 items)
  --notes-like: string # Filter by note words and #tags
  --started-at-greater: string # Filter by the date the user started the media
  --started-at-lesser: string # Filter by the date the user started the media
  --started-at-like: string # Filter by the date the user started the media
  --completed-at-greater: string # Filter by the date the user completed the media
  --completed-at-lesser: string # Filter by the date the user completed the media
  --completed-at-like: string # Filter by the date the user completed the media
  --qp-sort: string@sort-completer-5 # The order the results will be returned in
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"id": $id, "userId": $user_id, "userName": $user_name, "type": $type, "status": $status, "mediaId": $media_id, "isFollowing": $is_following, "notes": $notes, "startedAt": $started_at, "completedAt": $completed_at, "compareWithAuthList": $compare_with_auth_list, "userId_in": $user_id_in, "status_in": $status_in, "status_not_in": $status_not_in, "status_not": $status_not, "mediaId_in": $media_id_in, "mediaId_not_in": $media_id_not_in, "notes_like": $notes_like, "startedAt_greater": $started_at_greater, "startedAt_lesser": $started_at_lesser, "startedAt_like": $started_at_like, "completedAt_greater": $completed_at_greater, "completedAt_lesser": $completed_at_lesser, "completedAt_like": $completed_at_like, "sort": $qp_sort} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "id userId mediaId status score progress progressVolumes repeat priority private notes hiddenFromStatusLists customLists advancedScores updatedAt createdAt" }
    let body = {query: ("query($id: Int, $userId: Int, $userName: String, $type: MediaType, $status: MediaListStatus, $mediaId: Int, $isFollowing: Boolean, $notes: String, $startedAt: FuzzyDateInt, $completedAt: FuzzyDateInt, $compareWithAuthList: Boolean, $userId_in: [Int], $status_in: [MediaListStatus], $status_not_in: [MediaListStatus], $status_not: MediaListStatus, $mediaId_in: [Int], $mediaId_not_in: [Int], $notes_like: String, $startedAt_greater: FuzzyDateInt, $startedAt_lesser: FuzzyDateInt, $startedAt_like: String, $completedAt_greater: FuzzyDateInt, $completedAt_lesser: FuzzyDateInt, $completedAt_like: String, $sort: [MediaListSort]) { MediaList(id: $id, userId: $userId, userName: $userName, type: $type, status: $status, mediaId: $mediaId, isFollowing: $isFollowing, notes: $notes, startedAt: $startedAt, completedAt: $completedAt, compareWithAuthList: $compareWithAuthList, userId_in: $userId_in, status_in: $status_in, status_not_in: $status_not_in, status_not: $status_not, mediaId_in: $mediaId_in, mediaId_not_in: $mediaId_not_in, notes_like: $notes_like, startedAt_greater: $startedAt_greater, startedAt_lesser: $startedAt_lesser, startedAt_like: $startedAt_like, completedAt_greater: $completedAt_greater, completedAt_lesser: $completedAt_lesser, completedAt_like: $completedAt_like, sort: $sort) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  }
  if $dry_run or $raw or $allow_errors { $result } else { unwrap-graphql $result "MediaList" }
}

# Media list collection query, provides list pre-grouped by status & custom lists. User ID and Media Type arguments required.
#
# operationId: MediaListCollection
export def "query media-list-collection" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --user-id: int # Filter by a user's id
  --user-name: string # Filter by a user's name
  --type: string@type-completer # Filter by the list entries media type
  --status: string@status-completer-1 # Filter by the watching/reading status
  --notes: string # Filter by note words and #tags
  --started-at: string # Filter by the date the user started the media
  --completed-at: string # Filter by the date the user completed the media
  --force-single-completed-list: oneof<nothing, bool> # Always return completed list entries in one group, overriding the user's split completed option.
  --chunk: int # Which chunk of list entries to load
  --per-chunk: int # The amount of entries per chunk, max 500
  --status-in: string@status-in-completer-1 # Filter by the watching/reading status (max 10,000 items)
  --status-not-in: string@status-not-in-completer-1 # Filter by the watching/reading status (max 10,000 items)
  --status-not: string@status-not-completer-1 # Filter by the watching/reading status
  --notes-like: string # Filter by note words and #tags
  --started-at-greater: string # Filter by the date the user started the media
  --started-at-lesser: string # Filter by the date the user started the media
  --started-at-like: string # Filter by the date the user started the media
  --completed-at-greater: string # Filter by the date the user completed the media
  --completed-at-lesser: string # Filter by the date the user completed the media
  --completed-at-like: string # Filter by the date the user completed the media
  --qp-sort: string@sort-completer-5 # The order the results will be returned in
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"userId": $user_id, "userName": $user_name, "type": $type, "status": $status, "notes": $notes, "startedAt": $started_at, "completedAt": $completed_at, "forceSingleCompletedList": $force_single_completed_list, "chunk": $chunk, "perChunk": $per_chunk, "status_in": $status_in, "status_not_in": $status_not_in, "status_not": $status_not, "notes_like": $notes_like, "startedAt_greater": $started_at_greater, "startedAt_lesser": $started_at_lesser, "startedAt_like": $started_at_like, "completedAt_greater": $completed_at_greater, "completedAt_lesser": $completed_at_lesser, "completedAt_like": $completed_at_like, "sort": $qp_sort} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "hasNextChunk" }
    let body = {query: ("query($userId: Int, $userName: String, $type: MediaType, $status: MediaListStatus, $notes: String, $startedAt: FuzzyDateInt, $completedAt: FuzzyDateInt, $forceSingleCompletedList: Boolean, $chunk: Int, $perChunk: Int, $status_in: [MediaListStatus], $status_not_in: [MediaListStatus], $status_not: MediaListStatus, $notes_like: String, $startedAt_greater: FuzzyDateInt, $startedAt_lesser: FuzzyDateInt, $startedAt_like: String, $completedAt_greater: FuzzyDateInt, $completedAt_lesser: FuzzyDateInt, $completedAt_like: String, $sort: [MediaListSort]) { MediaListCollection(userId: $userId, userName: $userName, type: $type, status: $status, notes: $notes, startedAt: $startedAt, completedAt: $completedAt, forceSingleCompletedList: $forceSingleCompletedList, chunk: $chunk, perChunk: $perChunk, status_in: $status_in, status_not_in: $status_not_in, status_not: $status_not, notes_like: $notes_like, startedAt_greater: $startedAt_greater, startedAt_lesser: $startedAt_lesser, startedAt_like: $startedAt_like, completedAt_greater: $completedAt_greater, completedAt_lesser: $completedAt_lesser, completedAt_like: $completedAt_like, sort: $sort) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  }
  if $dry_run or $raw or $allow_errors { $result } else { unwrap-graphql $result "MediaListCollection" }
}

# Collection of all the possible media genres
#
# operationId: GenreCollection
export def "query genre-collection" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
]: any -> list {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {}
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  } else {
    let body = {query: "query { GenreCollection }", variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  }
  if $dry_run or $raw or $allow_errors { $result } else { unwrap-graphql $result "GenreCollection" }
}

# Collection of all the possible media tags
#
# operationId: MediaTagCollection
export def "query media-tag-collection" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --status: int # Mod Only
]: any -> list {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"status": $status} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "id name description category rank isGeneralSpoiler isMediaSpoiler isAdult userId" }
    let body = {query: ("query($status: Int) { MediaTagCollection(status: $status) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  }
  if $dry_run or $raw or $allow_errors { $result } else { unwrap-graphql $result "MediaTagCollection" }
}

# User query
#
# operationId: User
export def "query user" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --id: int # Filter by the user id
  --name: string # Filter by the name of the user
  --is-moderator: oneof<nothing, bool> # Filter to moderators only if true
  --search: string # Filter by search query
  --qp-sort: string@sort-completer-6 # The order the results will be returned in
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"id": $id, "name": $name, "isModerator": $is_moderator, "search": $search, "sort": $qp_sort} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "id name about bannerImage isFollowing isFollower isBlocked bans unreadNotificationCount siteUrl donatorTier donatorBadge moderatorRoles createdAt updatedAt moderatorStatus" }
    let body = {query: ("query($id: Int, $name: String, $isModerator: Boolean, $search: String, $sort: [UserSort]) { User(id: $id, name: $name, isModerator: $isModerator, search: $search, sort: $sort) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  }
  if $dry_run or $raw or $allow_errors { $result } else { unwrap-graphql $result "User" }
}

# Get the currently authenticated user
#
# operationId: Viewer
export def "query viewer" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {}
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "id name about bannerImage isFollowing isFollower isBlocked bans unreadNotificationCount siteUrl donatorTier donatorBadge moderatorRoles createdAt updatedAt moderatorStatus" }
    let body = {query: ("query { Viewer { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  }
  if $dry_run or $raw or $allow_errors { $result } else { unwrap-graphql $result "Viewer" }
}

# Notification query
#
# operationId: Notification
export def "query notification" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --type: string@type-completer-1 # Filter by the type of notifications
  --reset-notification-count: oneof<nothing, bool> # Reset the unread notification count to 0 on load
  --type-in: string@type-in-completer # Filter by the type of notifications (max 10,000 items)
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"type": $type, "resetNotificationCount": $reset_notification_count, "type_in": $type_in} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "__typename ... on AiringNotification { id type animeId episode contexts createdAt } ... on FollowingNotification { id userId type context createdAt } ... on ActivityMessageNotification { id userId type activityId context createdAt }" }
    let body = {query: ("query($type: NotificationType, $resetNotificationCount: Boolean, $type_in: [NotificationType]) { Notification(type: $type, resetNotificationCount: $resetNotificationCount, type_in: $type_in) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  }
  if $dry_run or $raw or $allow_errors { $result } else { unwrap-graphql $result "Notification" }
}

# Studio query
#
# operationId: Studio
export def "query studio" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --id: int # Filter by the studio id
  --search: string # Filter by search query
  --id-not: int # Filter by the studio id
  --id-in: int # Filter by the studio id (max 10,000 items)
  --id-not-in: int # Filter by the studio id (max 10,000 items)
  --qp-sort: string@sort-completer-7 # The order the results will be returned in
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"id": $id, "search": $search, "id_not": $id_not, "id_in": $id_in, "id_not_in": $id_not_in, "sort": $qp_sort} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "id name isAnimationStudio siteUrl isFavourite favourites" }
    let body = {query: ("query($id: Int, $search: String, $id_not: Int, $id_in: [Int], $id_not_in: [Int], $sort: [StudioSort]) { Studio(id: $id, search: $search, id_not: $id_not, id_in: $id_in, id_not_in: $id_not_in, sort: $sort) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  }
  if $dry_run or $raw or $allow_errors { $result } else { unwrap-graphql $result "Studio" }
}

# Review query
#
# operationId: Review
export def "query review" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --id: int # Filter by Review id
  --media-id: int # Filter by media id
  --user-id: int # Filter by user id
  --media-type: string@media-type-completer # Filter by media type
  --qp-sort: string@sort-completer-8 # The order the results will be returned in
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"id": $id, "mediaId": $media_id, "userId": $user_id, "mediaType": $media_type, "sort": $qp_sort} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "id userId mediaId mediaType summary body rating ratingAmount userRating score private siteUrl createdAt updatedAt" }
    let body = {query: ("query($id: Int, $mediaId: Int, $userId: Int, $mediaType: MediaType, $sort: [ReviewSort]) { Review(id: $id, mediaId: $mediaId, userId: $userId, mediaType: $mediaType, sort: $sort) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  }
  if $dry_run or $raw or $allow_errors { $result } else { unwrap-graphql $result "Review" }
}

# GraphQL mutation: UpdateUser
#
# operationId: UpdateUser
# --notification-options item shape: {type?: "ACTIVITY_MESSAGE"|"ACTIVITY_REPLY"|"FOLLOWING"|"ACTIVITY_MENTION"|"THREAD_COMMENT_MENTION"|"THREAD_SUBSCRIBED"|"THREAD_COMMENT_REPLY"|"AIRING"|"ACTIVITY_LIKE"|"ACTIVITY_REPLY_LIKE"|"THREAD_LIKE"|"THREAD_COMMENT_LIKE"|"ACTIVITY_REPLY_SUBSCRIBED"|"RELATED_MEDIA_ADDITION"|"MEDIA_DATA_CHANGE"|"MEDIA_MERGE"|"MEDIA_DELETION"|"MEDIA_SUBMISSION_UPDATE"|"STAFF_SUBMISSION_UPDATE"|"CHARACTER_SUBMISSION_UPDATE", enabled?: bool}
# --disabled-list-activity item shape: {disabled?: bool, type?: "CURRENT"|"PLANNING"|"COMPLETED"|"DROPPED"|"PAUSED"|"REPEATING"}
export def "mutation update-user" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --about: string # User's about/bio text
  --title-language: string@title-language-completer # User's title language
  --display-adult-content: oneof<nothing, bool> # If the user should see media marked as adult-only
  --airing-notifications: oneof<nothing, bool> # If the user should get notifications when a show they are watching aires
  --score-format: string@score-format-completer # The user's list scoring system
  --row-order: string # The user's default list order
  --profile-color: string # Profile highlight color
  --donator-badge: string # Profile highlight color
  --notification-options: record # Notification options — item shape: {type?: "ACTIVITY_MESSAGE"|"ACTIVITY_REPLY"|"FOLLOWING"|"ACTIVITY_MENTION"|"THREAD_COMMENT_MENTION"|"THREAD_SUBSCRIBED"|"THREAD_COMMENT_REPLY"|"AIRING"|"ACTIVITY_LIKE"|"ACTIVITY_REPLY_LIKE"|"THREAD_LIKE"|"THREAD_COMMENT_LIKE"|"ACTIVITY_REPLY_SUBSCRIBED"|"RELATED_MEDIA_ADDITION"|"MEDIA_DATA_CHANGE"|"MEDIA_MERGE"|"MEDIA_DELETION"|"MEDIA_SUBMISSION_UPDATE"|"STAFF_SUBMISSION_UPDATE"|"CHARACTER_SUBMISSION_UPDATE", enabled?: bool}
  --timezone: string # Timezone offset format: -?HH:MM
  --activity-merge-time: int # Minutes between activity for them to be merged together. 0 is Never, Above 2 weeks (20160 mins) is Always.
  --staff-name-language: string@staff-name-language-completer # The language the user wants to see staff and character names in
  --restrict-messages-to-following: oneof<nothing, bool> # Only allow messages from other users the user follows
  --disabled-list-activity: record # item shape: {disabled?: bool, type?: "CURRENT"|"PLANNING"|"COMPLETED"|"DROPPED"|"PAUSED"|"REPEATING"}
  --anime-list-options-sectionOrder: string # The order each list should be displayed in
  --anime-list-options-splitCompletedSectionByFormat: oneof<nothing, bool> # If the completed sections of the list should be separated by format
  --anime-list-options-customLists: string # The names of the user's custom lists
  --anime-list-options-advancedScoring: string # The names of the user's advanced scoring sections
  --anime-list-options-advancedScoringEnabled: oneof<nothing, bool> # If advanced scoring is enabled
  --anime-list-options-theme: string # list theme
  --manga-list-options-sectionOrder: string # The order each list should be displayed in
  --manga-list-options-splitCompletedSectionByFormat: oneof<nothing, bool> # If the completed sections of the list should be separated by format
  --manga-list-options-customLists: string # The names of the user's custom lists
  --manga-list-options-advancedScoring: string # The names of the user's advanced scoring sections
  --manga-list-options-advancedScoringEnabled: oneof<nothing, bool> # If advanced scoring is enabled
  --manga-list-options-theme: string # list theme
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let animeListOptions = ({"sectionOrder": $anime_list_options_sectionOrder, "splitCompletedSectionByFormat": $anime_list_options_splitCompletedSectionByFormat, "customLists": $anime_list_options_customLists, "advancedScoring": $anime_list_options_advancedScoring, "advancedScoringEnabled": $anime_list_options_advancedScoringEnabled, "theme": $anime_list_options_theme} | compact | if ($in | is-empty) { null } else { $in })
  let mangaListOptions = ({"sectionOrder": $manga_list_options_sectionOrder, "splitCompletedSectionByFormat": $manga_list_options_splitCompletedSectionByFormat, "customLists": $manga_list_options_customLists, "advancedScoring": $manga_list_options_advancedScoring, "advancedScoringEnabled": $manga_list_options_advancedScoringEnabled, "theme": $manga_list_options_theme} | compact | if ($in | is-empty) { null } else { $in })
  let variables = {"about": $about, "titleLanguage": $title_language, "displayAdultContent": $display_adult_content, "airingNotifications": $airing_notifications, "scoreFormat": $score_format, "rowOrder": $row_order, "profileColor": $profile_color, "donatorBadge": $donator_badge, "notificationOptions": $notification_options, "timezone": $timezone, "activityMergeTime": $activity_merge_time, "staffNameLanguage": $staff_name_language, "restrictMessagesToFollowing": $restrict_messages_to_following, "disabledListActivity": $disabled_list_activity, "animeListOptions": $animeListOptions, "mangaListOptions": $mangaListOptions} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "id name about bannerImage isFollowing isFollower isBlocked bans unreadNotificationCount siteUrl donatorTier donatorBadge moderatorRoles createdAt updatedAt moderatorStatus" }
    let body = {query: ("mutation($about: String, $titleLanguage: UserTitleLanguage, $displayAdultContent: Boolean, $airingNotifications: Boolean, $scoreFormat: ScoreFormat, $rowOrder: String, $profileColor: String, $donatorBadge: String, $notificationOptions: [NotificationOptionInput], $timezone: String, $activityMergeTime: Int, $animeListOptions: MediaListOptionsInput, $mangaListOptions: MediaListOptionsInput, $staffNameLanguage: UserStaffNameLanguage, $restrictMessagesToFollowing: Boolean, $disabledListActivity: [ListActivityOptionInput]) { UpdateUser(about: $about, titleLanguage: $titleLanguage, displayAdultContent: $displayAdultContent, airingNotifications: $airingNotifications, scoreFormat: $scoreFormat, rowOrder: $rowOrder, profileColor: $profileColor, donatorBadge: $donatorBadge, notificationOptions: $notificationOptions, timezone: $timezone, activityMergeTime: $activityMergeTime, staffNameLanguage: $staffNameLanguage, restrictMessagesToFollowing: $restrictMessagesToFollowing, disabledListActivity: $disabledListActivity, animeListOptions: $animeListOptions, mangaListOptions: $mangaListOptions) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  }
  if $dry_run or $raw or $allow_errors { $result } else { unwrap-graphql $result "UpdateUser" }
}

# Create or update a media list entry
#
# operationId: SaveMediaListEntry
export def "mutation save-media-list-entry" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --id: int # The list entry id, required for updating
  --media-id: int # The id of the media the entry is of
  --status: string@status-completer-1 # The watching/reading status
  --score: float # The score of the media in the user's chosen scoring method
  --score-raw: int # The score of the media in 100 point
  --progress: int # The amount of episodes/chapters consumed by the user
  --progress-volumes: int # The amount of volumes read by the user
  --repeat: int # The amount of times the user has rewatched/read the media
  --priority: int # Priority of planning
  --private: oneof<nothing, bool> # If the entry should only be visible to authenticated user
  --notes: string # Text notes
  --hidden-from-status-lists: oneof<nothing, bool> # If the entry shown be hidden from non-custom lists
  --custom-lists: string # Array of custom list names which should be enabled for this entry
  --advanced-scores: float # Array of advanced scores
  --started-at-year: int # Numeric Year (2017)
  --started-at-month: int # Numeric Month (3)
  --started-at-day: int # Numeric Day (24)
  --completed-at-year: int # Numeric Year (2017)
  --completed-at-month: int # Numeric Month (3)
  --completed-at-day: int # Numeric Day (24)
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let startedAt = ({"year": $started_at_year, "month": $started_at_month, "day": $started_at_day} | compact | if ($in | is-empty) { null } else { $in })
  let completedAt = ({"year": $completed_at_year, "month": $completed_at_month, "day": $completed_at_day} | compact | if ($in | is-empty) { null } else { $in })
  let variables = {"id": $id, "mediaId": $media_id, "status": $status, "score": $score, "scoreRaw": $score_raw, "progress": $progress, "progressVolumes": $progress_volumes, "repeat": $repeat, "priority": $priority, "private": $private, "notes": $notes, "hiddenFromStatusLists": $hidden_from_status_lists, "customLists": $custom_lists, "advancedScores": $advanced_scores, "startedAt": $startedAt, "completedAt": $completedAt} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "id userId mediaId status score progress progressVolumes repeat priority private notes hiddenFromStatusLists customLists advancedScores updatedAt createdAt" }
    let body = {query: ("mutation($id: Int, $mediaId: Int, $status: MediaListStatus, $score: Float, $scoreRaw: Int, $progress: Int, $progressVolumes: Int, $repeat: Int, $priority: Int, $private: Boolean, $notes: String, $hiddenFromStatusLists: Boolean, $customLists: [String], $advancedScores: [Float], $startedAt: FuzzyDateInput, $completedAt: FuzzyDateInput) { SaveMediaListEntry(id: $id, mediaId: $mediaId, status: $status, score: $score, scoreRaw: $scoreRaw, progress: $progress, progressVolumes: $progressVolumes, repeat: $repeat, priority: $priority, private: $private, notes: $notes, hiddenFromStatusLists: $hiddenFromStatusLists, customLists: $customLists, advancedScores: $advancedScores, startedAt: $startedAt, completedAt: $completedAt) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  }
  if $dry_run or $raw or $allow_errors { $result } else { unwrap-graphql $result "SaveMediaListEntry" }
}

# Update multiple media list entries to the same values
#
# operationId: UpdateMediaListEntries
export def "mutation update-media-list-entries" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --status: string@status-completer-1 # The watching/reading status
  --score: float # The score of the media in the user's chosen scoring method
  --score-raw: int # The score of the media in 100 point
  --progress: int # The amount of episodes/chapters consumed by the user
  --progress-volumes: int # The amount of volumes read by the user
  --repeat: int # The amount of times the user has rewatched/read the media
  --priority: int # Priority of planning
  --private: oneof<nothing, bool> # If the entry should only be visible to authenticated user
  --notes: string # Text notes
  --hidden-from-status-lists: oneof<nothing, bool> # If the entry shown be hidden from non-custom lists
  --advanced-scores: float # Array of advanced scores
  --ids: int # The list entries ids to update
  --started-at-year: int # Numeric Year (2017)
  --started-at-month: int # Numeric Month (3)
  --started-at-day: int # Numeric Day (24)
  --completed-at-year: int # Numeric Year (2017)
  --completed-at-month: int # Numeric Month (3)
  --completed-at-day: int # Numeric Day (24)
]: any -> list {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let startedAt = ({"year": $started_at_year, "month": $started_at_month, "day": $started_at_day} | compact | if ($in | is-empty) { null } else { $in })
  let completedAt = ({"year": $completed_at_year, "month": $completed_at_month, "day": $completed_at_day} | compact | if ($in | is-empty) { null } else { $in })
  let variables = {"status": $status, "score": $score, "scoreRaw": $score_raw, "progress": $progress, "progressVolumes": $progress_volumes, "repeat": $repeat, "priority": $priority, "private": $private, "notes": $notes, "hiddenFromStatusLists": $hidden_from_status_lists, "advancedScores": $advanced_scores, "ids": $ids, "startedAt": $startedAt, "completedAt": $completedAt} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "id userId mediaId status score progress progressVolumes repeat priority private notes hiddenFromStatusLists customLists advancedScores updatedAt createdAt" }
    let body = {query: ("mutation($status: MediaListStatus, $score: Float, $scoreRaw: Int, $progress: Int, $progressVolumes: Int, $repeat: Int, $priority: Int, $private: Boolean, $notes: String, $hiddenFromStatusLists: Boolean, $advancedScores: [Float], $startedAt: FuzzyDateInput, $completedAt: FuzzyDateInput, $ids: [Int]) { UpdateMediaListEntries(status: $status, score: $score, scoreRaw: $scoreRaw, progress: $progress, progressVolumes: $progressVolumes, repeat: $repeat, priority: $priority, private: $private, notes: $notes, hiddenFromStatusLists: $hiddenFromStatusLists, advancedScores: $advancedScores, ids: $ids, startedAt: $startedAt, completedAt: $completedAt) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  }
  if $dry_run or $raw or $allow_errors { $result } else { unwrap-graphql $result "UpdateMediaListEntries" }
}

# Delete a media list entry
#
# operationId: DeleteMediaListEntry
export def "mutation delete-media-list-entry" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --id: int # The id of the media list entry to delete
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"id": $id} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "deleted" }
    let body = {query: ("mutation($id: Int) { DeleteMediaListEntry(id: $id) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  }
  if $dry_run or $raw or $allow_errors { $result } else { unwrap-graphql $result "DeleteMediaListEntry" }
}

# Delete a custom list and remove the list entries from it
#
# operationId: DeleteCustomList
export def "mutation delete-custom-list" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --custom-list: string # The name of the custom list to delete
  --type: string@type-completer # The media list type of the custom list
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"customList": $custom_list, "type": $type} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "deleted" }
    let body = {query: ("mutation($customList: String, $type: MediaType) { DeleteCustomList(customList: $customList, type: $type) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  }
  if $dry_run or $raw or $allow_errors { $result } else { unwrap-graphql $result "DeleteCustomList" }
}

# Create or update text activity for the currently authenticated user
#
# operationId: SaveTextActivity
export def "mutation save-text-activity" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --id: int # The activity's id, required for updating
  --text: string # The activity text
  --locked: oneof<nothing, bool> # If the activity should be locked. (Mod Only)
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"id": $id, "text": $text, "locked": $locked} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "id userId type replyCount text siteUrl isLocked isSubscribed likeCount isLiked isPinned createdAt" }
    let body = {query: ("mutation($id: Int, $text: String, $locked: Boolean) { SaveTextActivity(id: $id, text: $text, locked: $locked) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  }
  if $dry_run or $raw or $allow_errors { $result } else { unwrap-graphql $result "SaveTextActivity" }
}

# Create or update message activity for the currently authenticated user
#
# operationId: SaveMessageActivity
export def "mutation save-message-activity" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --id: int # The activity id, required for updating
  --message: string # The activity message text
  --recipient-id: int # The id of the user the message is being sent to
  --private: oneof<nothing, bool> # If the activity should be private
  --locked: oneof<nothing, bool> # If the activity should be locked. (Mod Only)
  --as-mod: oneof<nothing, bool> # If the message should be sent from the Moderator account (Mod Only)
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"id": $id, "message": $message, "recipientId": $recipient_id, "private": $private, "locked": $locked, "asMod": $as_mod} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "id recipientId messengerId type replyCount message isLocked isSubscribed likeCount isLiked isPinned isPrivate siteUrl createdAt" }
    let body = {query: ("mutation($id: Int, $message: String, $recipientId: Int, $private: Boolean, $locked: Boolean, $asMod: Boolean) { SaveMessageActivity(id: $id, message: $message, recipientId: $recipientId, private: $private, locked: $locked, asMod: $asMod) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  }
  if $dry_run or $raw or $allow_errors { $result } else { unwrap-graphql $result "SaveMessageActivity" }
}

# Update list activity (Mod Only)
#
# operationId: SaveListActivity
export def "mutation save-list-activity" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --id: int # The activity's id, required for updating
  --locked: oneof<nothing, bool> # If the activity should be locked. (Mod Only)
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"id": $id, "locked": $locked} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "id userId type replyCount status progress isLocked isSubscribed likeCount isLiked isPinned siteUrl createdAt" }
    let body = {query: ("mutation($id: Int, $locked: Boolean) { SaveListActivity(id: $id, locked: $locked) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  }
  if $dry_run or $raw or $allow_errors { $result } else { unwrap-graphql $result "SaveListActivity" }
}

# Delete an activity item of the authenticated users
#
# operationId: DeleteActivity
export def "mutation delete-activity" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --id: int # The id of the activity to delete
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"id": $id} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "deleted" }
    let body = {query: ("mutation($id: Int) { DeleteActivity(id: $id) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  }
  if $dry_run or $raw or $allow_errors { $result } else { unwrap-graphql $result "DeleteActivity" }
}

# Toggle activity to be pinned to the top of the user's activity feed
#
# operationId: ToggleActivityPin
export def "mutation toggle-activity-pin" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --id: int # Toggle activity id to be pinned
  --pinned: oneof<nothing, bool> # If the activity should be pinned or unpinned
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"id": $id, "pinned": $pinned} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "__typename ... on TextActivity { id userId type replyCount text siteUrl isLocked isSubscribed likeCount isLiked isPinned createdAt } ... on ListActivity { id userId type replyCount status progress isLocked isSubscribed likeCount isLiked isPinned siteUrl createdAt } ... on MessageActivity { id recipientId messengerId type replyCount message isLocked isSubscribed likeCount isLiked isPinned isPrivate siteUrl createdAt }" }
    let body = {query: ("mutation($id: Int, $pinned: Boolean) { ToggleActivityPin(id: $id, pinned: $pinned) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  }
  if $dry_run or $raw or $allow_errors { $result } else { unwrap-graphql $result "ToggleActivityPin" }
}

# Toggle the subscription of an activity item
#
# operationId: ToggleActivitySubscription
export def "mutation toggle-activity-subscription" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --activity-id: int # The id of the activity to un/subscribe
  --subscribe: oneof<nothing, bool> # Whether to subscribe or unsubscribe from the activity
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"activityId": $activity_id, "subscribe": $subscribe} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "__typename ... on TextActivity { id userId type replyCount text siteUrl isLocked isSubscribed likeCount isLiked isPinned createdAt } ... on ListActivity { id userId type replyCount status progress isLocked isSubscribed likeCount isLiked isPinned siteUrl createdAt } ... on MessageActivity { id recipientId messengerId type replyCount message isLocked isSubscribed likeCount isLiked isPinned isPrivate siteUrl createdAt }" }
    let body = {query: ("mutation($activityId: Int, $subscribe: Boolean) { ToggleActivitySubscription(activityId: $activityId, subscribe: $subscribe) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  }
  if $dry_run or $raw or $allow_errors { $result } else { unwrap-graphql $result "ToggleActivitySubscription" }
}

# Create or update an activity reply
#
# operationId: SaveActivityReply
export def "mutation save-activity-reply" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --id: int # The activity reply id, required for updating
  --activity-id: int # The id of the parent activity being replied to
  --text: string # The reply text
  --as-mod: oneof<nothing, bool> # If the reply should be sent from the Moderator account (Mod Only)
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"id": $id, "activityId": $activity_id, "text": $text, "asMod": $as_mod} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "id userId activityId text likeCount isLiked createdAt" }
    let body = {query: ("mutation($id: Int, $activityId: Int, $text: String, $asMod: Boolean) { SaveActivityReply(id: $id, activityId: $activityId, text: $text, asMod: $asMod) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  }
  if $dry_run or $raw or $allow_errors { $result } else { unwrap-graphql $result "SaveActivityReply" }
}

# Delete an activity reply of the authenticated users
#
# operationId: DeleteActivityReply
export def "mutation delete-activity-reply" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --id: int # The id of the reply to delete
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"id": $id} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "deleted" }
    let body = {query: ("mutation($id: Int) { DeleteActivityReply(id: $id) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  }
  if $dry_run or $raw or $allow_errors { $result } else { unwrap-graphql $result "DeleteActivityReply" }
}

# Add or remove a like from a likeable type.                           Returns all the users who liked the same model
#
# operationId: ToggleLike
export def "mutation toggle-like" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --id: int # The id of the likeable type
  --type: string@type-completer-2 # The type of model to be un/liked
]: any -> list {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"id": $id, "type": $type} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "id name about bannerImage isFollowing isFollower isBlocked bans unreadNotificationCount siteUrl donatorTier donatorBadge moderatorRoles createdAt updatedAt moderatorStatus" }
    let body = {query: ("mutation($id: Int, $type: LikeableType) { ToggleLike(id: $id, type: $type) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  }
  if $dry_run or $raw or $allow_errors { $result } else { unwrap-graphql $result "ToggleLike" }
}

# Add or remove a like from a likeable type.
#
# operationId: ToggleLikeV2
export def "mutation toggle-like-v2" [
  --base-url(-b): string@base-url-completer # API base URL
  --token(-t): string # Auth token
  --auth-scheme(-a): string@auth-scheme-completer # Auth scheme
  --insecure(-k) # Skip TLS verification
  --max-time(-m): duration # Timeout
  --raw(-r) # Fetch as text
  --allow-errors(-e) # Return full response without error handling
  --dry-run(-n) # Return the request that would be sent without executing it
  --fields: list<string> # Fields to select
  --query: string # Raw GraphQL query (overrides auto-generated)
  --id: int # The id of the likeable type
  --type: string@type-completer-2 # The type of model to be un/liked
]: any -> record {
  let input = $in
  let auth = (build-auth $token ($auth_scheme | default $DEFAULT_AUTH))
  let base = ($base_url | default $BASE_URL)
  let variables = {"id": $id, "type": $type} | compact
  let variables = if ($input | describe | str starts-with "record") { $input | merge deep $variables } else { $variables }
  let result = if ($query | is-not-empty) {
    let body = {query: $query, variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  } else {
    let sel = if ($fields | is-not-empty) { $fields | str join " " } else { "__typename ... on ListActivity { id userId type replyCount status progress isLocked isSubscribed likeCount isLiked isPinned siteUrl createdAt } ... on TextActivity { id userId type replyCount text siteUrl isLocked isSubscribed likeCount isLiked isPinned createdAt } ... on MessageActivity { id recipientId messengerId type replyCount message isLocked isSubscribed likeCount isLiked isPinned isPrivate siteUrl createdAt }" }
    let body = {query: ("mutation($id: Int, $type: LikeableType) { ToggleLikeV2(id: $id, type: $type) { " + $sel + " } }"), variables: $variables}
    do-request "post" $base $auth $insecure $raw $dry_run $max_time $allow_errors "application/json" $body
  }
  if $dry_run or $raw or $allow_errors { $result } else { unwrap-graphql $result "ToggleLikeV2" }
}
