# OmniSocials Ruby SDK

The official Ruby SDK for OmniSocials: post, schedule, reply and report on 13 social platforms (Instagram, Facebook, LinkedIn, X, TikTok, YouTube, Threads, Pinterest, Bluesky, Mastodon, Google Business, Telegram and Discord) from one API. Guide: [omnisocials.com/sdk/ruby](https://omnisocials.com/sdk/ruby)

Full API reference: [https://docs.omnisocials.com](https://docs.omnisocials.com)

## Install

```bash
gem install omnisocials
```

Or in your Gemfile:

```ruby
gem "omnisocials"
```

Requires Ruby 3.0+. Zero runtime dependencies: built entirely on the Ruby standard library (Net::HTTP, OpenSSL, JSON).

## Quickstart

```ruby
require "omnisocials"

client = OmniSocials::Client.new  # reads OMNISOCIALS_API_KEY from the environment
post = client.posts.create(content: "Hello from Ruby", channels: ["instagram", "linkedin"])
puts post["data"]["id"]
```

## Authentication

Create an API key in the OmniSocials app under **Settings -> API Keys**. Keys start with `omsk_live_` and are bound to one workspace. There are no test keys and no test mode: every key works on your real connected accounts. To try things safely, leave out `scheduled_at` so the post stays a draft (a draft never publishes on its own), or use a separate workspace with test accounts.

Pass the key explicitly or set the `OMNISOCIALS_API_KEY` environment variable:

```ruby
require "omnisocials"

client = OmniSocials::Client.new(api_key: "omsk_live_...")
# or: export OMNISOCIALS_API_KEY=omsk_live_... and just OmniSocials::Client.new
```

The client opens a fresh connection per request, so there is nothing to close. All responses are plain Hashes (parsed JSON, string keys), returned exactly as the API sends them.

## Posts

### Schedule a post

```ruby
post = client.posts.create(
  content: "Big announcement coming Friday",
  channels: ["instagram", "facebook", "linkedin"],
  scheduled_at: "2026-08-01T09:00:00Z",
  media_urls: ["https://example.com/teaser.jpg"]
)
```

Omit `scheduled_at` to create a draft, or use `create_and_publish` to publish immediately:

```ruby
post = client.posts.create_and_publish(
  content: "We are live!",
  channels: ["x", "bluesky"]
)
```

### Planned drafts

Pass `draft: true` with `scheduled_at` to store the post as a draft that keeps its time. It shows on the dashboard calendar at that slot with a dashed outline and the scheduler never publishes it: a person schedules it from the composer, or you do with `update` and `draft: false`. Use it when an agent proposes a slot that a human should confirm. `draft: true` is not allowed with `publish_now` or `approval_workflow_id` (`400 validation_error`). On `update`, `draft: false` without `scheduled_at` is a `400 validation_error` when the draft has no time or its time is in the past (pass a new `scheduled_at` then), and `draft: true` on a scheduled post unschedules it while keeping the time.

```ruby
proposal = client.posts.create(
  content: "Proposed for Friday morning",
  channels: ["instagram", "linkedin"],
  scheduled_at: "2026-08-01T09:00:00Z",
  draft: true
)
puts proposal["data"]["status"], proposal["data"]["schedule_at"] # draft, the time is kept

# The human agrees: schedule it at the time it already carries
client.posts.update(proposal["data"]["id"], draft: false)
```

### Comment-to-DM automations

Answer a keyword in an Instagram comment with a DM, once per person, with an optional public reply under the comment. Pass `comment_dm_automation:` on `create` (Instagram must be in `channels`) and the automation is bound to that post; it starts listening once the post is live. Needs the opt-in `automations:write` scope on the key. `client.automations` manages the automations themselves (`list`, `get`, `create`, `update`, `delete`) and reads their activity (`list_events`, `automations:read`). On `update`, `comment_dm_automation:` as a Hash replaces the post's automation and an explicit `nil` removes it. Instagram rules: one private reply per comment, within 7 days; OmniSocials caps sends at 180 DMs an hour per account.

```ruby
post = client.posts.create(
  content: "Comment GUIDE and I will send you the link",
  channels: ["instagram"],
  scheduled_at: "2026-08-01T09:00:00Z",
  media_urls: ["https://example.com/guide-cover.jpg"],
  comment_dm_automation: {
    "trigger" => { "keywords" => ["guide"], "match" => "word" },
    "actions" => {
      "dm" => { "text" => "Here is the guide: https://example.com/guide" },
      "public_reply" => { "enabled" => true, "variations" => ["Sent you a DM!", "Check your inbox"] }
    },
    "limits" => { "max_sends" => 500 }
  }
)
automation_id = post["data"]["comment_dm_automation"]["id"]

# Later: who was answered, and why someone was skipped
events = client.automations.list_events(automation_id, outcome: "sent")
puts events["counts"] # { "sent" => 12, "skipped" => 3 }
events["data"].each do |event|
  puts [event["person"]["username"], event["outcome"], event["reason_label"]].join(" ")
end
```

The events response is `{ "data", "counts", "pagination" }`, not the plain list: `counts` is the number of events per outcome (`sent`, `skipped`, `failed`, `pending`, `queued`, `opted_out`, `waiting`). An automation can also listen on a post published outside OmniSocials (`client.automations.create(instagram_media_id: ..., actions: ...)`), on the next post the workspace publishes (`trigger: { "scope" => "next_post" }`) or on every post (`"scope" => "any"`), and on DMs and story replies (`trigger: { "kinds" => ["dm", "story_reply"], ... }`).

Follow first (`"follow_gate"` in the actions, Instagram only) sends the link only to people who follow the account. On a comment the private reply is a first message with one button; a tap makes OmniSocials ask Instagram whether the person follows. A follower gets the DM text, anyone else gets the `not_following` message with its button, and every later tap checks again. A DM or a story reply is checked at once. When Instagram gives no answer the link goes out anyway. Texts hold 640 characters and buttons 20; leave them out for the defaults. A person who has not followed yet is an event with outcome `waiting` and `event["follow_gate"]` (`state`, `taps`, `followed`, `checked`, `after_ask`); `stats["followed"]` counts the people who followed after the ask. `"enabled" => true` on a Facebook or X automation is a `400 follow_gate_instagram_only`.

```ruby
client.automations.update(
  automation_id,
  actions: {
    "dm" => { "text" => "Here is the guide: https://example.com/guide" },
    "follow_gate" => {
      "enabled" => true,
      "first_message" => { "text" => "Tap the button and I'll send you the link 👇", "button" => "Send me the link" },
      "not_following" => { "text" => "Almost there! Follow @yourbrand first, then tap the button again.", "button" => "I follow now" }
    }
  }
)
```

A Facebook Page works the same way, and the DM lands in Messenger: pass `platform: "facebook"` to `client.automations.create`, or `facebook_post_id: ...` for a Page post published outside OmniSocials. On a post, `comment_dm_automation: { "platforms" => ["instagram", "facebook"], ... }` makes one automation per channel with the same keywords and DM. Facebook has no story replies.

On X, pass `platform: "x"` with `trigger: { "kinds" => ["dm"], "keywords" => ["guide"] }`: the X account answers a keyword in a DM, once per person, and every answer ends with "Reply STOP to stop automatic messages." An active X automation needs X DMs on for the workspace (`409 x_dms_off`; `status: "paused"` always saves). An answer over the send cap waits in a queue (`queued`) for up to an hour.

### Per-media alt text

Every `media_urls` / `media_ids` entry accepts either a plain String or a Hash with an `alt` accessibility description (max 1500 chars). Alt text is delivered to Mastodon (media description), Bluesky (embed alt), X (photos and GIFs), Pinterest (pin alt text), Instagram (images), and LinkedIn (images). Strings and Hashes can be mixed, and the same shape works in per-platform Hashes and `thread_parts` media.

```ruby
post = client.posts.create(
  content: "Sunrise over the harbor",
  channels: ["mastodon", "bluesky"],
  scheduled_at: "2026-08-01T09:00:00Z",
  media_urls: [
    {
      "url" => "https://example.com/harbor.jpg",
      "alt" => "A small sailboat crossing a calm harbor at sunrise, sky in deep orange"
    }
  ]
)
```

### Post to specific platforms with platform options

`content` can be a per-platform Hash (with `default` as the fallback), and each platform has its own options Hash:

```ruby
post = client.posts.create(
  content: {
    "default" => "New feature: best times to post",
    "linkedin" => "We just shipped best times to post. Here is how it works."
  },
  channels: ["linkedin", "instagram", "youtube"],
  media_urls: ["https://example.com/demo.mp4"],
  scheduled_at: "2026-08-01T09:00:00Z",
  instagram: { "share_to_feed" => true },
  youtube: { "title" => "Best times to post, explained", "privacy_status" => "public" }
)
```

Note that `linkedin` targets a personal LinkedIn profile and `linkedin_page` targets a LinkedIn company page. Both can be connected to the same workspace and posted to independently.

### Telegram channels and groups

`telegram` is a channel or group the workspace connected in OmniSocials; the OmniSocials bot posts to it. The `telegram` options: `silent`, `link_preview`, `pin`, `protect_content`, `spoiler` and `caption_above_media` (booleans), up to 3 `buttons` (`{ text, url }`, not on an album or a poll), a native `poll` (2 to 12 options of up to 100 characters, `open_period` 5 to 2628000 seconds, `multiple`; the post text is the question, max 300 characters, no media) and `first_comment` (a reply under the post). Text up to 4,096 characters; with media, text over 1,024 characters is sent as a reply under the media. Albums hold up to 10 photos and videos, files up to 50 MB, no Stories. Once sent, the post's `telegram.result` carries the message ids and the link. Telegram gives bots no view counts: analytics carry the reactions and the poll votes.

```ruby
client.posts.create(
  content: "The new collection is live. Tap the button to shop.",
  channels: ["telegram"],
  scheduled_at: "2026-11-02T09:00:00Z",
  media_urls: ["https://example.com/collection.jpg"],
  telegram: {
    "silent" => true,
    "pin" => true,
    "buttons" => [{ "text" => "Shop now", "url" => "https://example.com/shop" }],
    "first_comment" => "Questions? Reply to this message."
  }
)

# A native poll: the text is the question.
client.posts.create(
  content: "Which day suits the live Q&A?",
  channels: ["telegram"],
  telegram: { "poll" => { "options" => %w[Tuesday Thursday Saturday], "open_period" => 86_400 } }
)
```

### Discord channels

`discord` is one Discord channel the workspace connected in OmniSocials; the post goes out through the channel's incoming webhook and shows the webhook's name and picture. The `discord` options: `silent`, `link_preview` (default on), `allow_mentions` (default off, so @everyone, @here, role and user mentions show as text and ping nobody) and `spoiler` (booleans), `thread_name` (the post title in a forum or media channel, 1 to 100 characters), up to 5 `buttons` (`{ text, url }`, one row, not with a poll) and a native `poll` (2 to 10 options of up to 55 characters, `duration_hours` 1 to 768, default 24, `multiple`; the post text is the question, max 300 characters, no media). Text up to 2,000 characters. Up to 10 images, GIFs and videos per message; a video or GIF over Discord's 20 MB attachment limit is sent as a link in the text. No Stories. Once sent, the post's `discord.result` carries the message id and the link. Discord gives webhooks no view counts: analytics carry the reactions and the poll votes.

```ruby
client.posts.create(
  content: "Patch 2.4 is out. Read the notes below.",
  channels: ["discord"],
  scheduled_at: "2026-11-02T09:00:00Z",
  media_urls: ["https://example.com/patch-notes.png"],
  discord: {
    "silent" => true,
    "buttons" => [{ "text" => "Patch notes", "url" => "https://example.com/patch-2-4" }]
  }
)

# A native poll: the text is the question.
client.posts.create(
  content: "Which mode do we test next?",
  channels: ["discord"],
  discord: { "poll" => { "options" => %w[Ranked Co-op Arena], "duration_hours" => 48 } }
)
```

### Chained threads (X, Bluesky, Mastodon, Threads)

Pass 2 to 25 `thread_parts` to publish a chained thread instead of a single tweet (each part is at most 280 characters, 25,000 for X Premium/Premium+ accounts). Bluesky, Mastodon and Threads support the same `thread_parts` shape (Threads: 2 to 25 parts, 500 characters per part, up to 10 media per part; parts after the first publish as replies to the previous part, and the Threads caption is taken from part 1):

```ruby
post = client.posts.create(
  content: "How we cut our API response times by 80%",  # fallback text
  channels: ["x"],
  scheduled_at: "2026-08-01T15:00:00Z",
  x: {
    "thread_parts" => [
      { "text" => "How we cut our API response times by 80%. A thread:" },
      { "text" => "1/ We started by profiling every endpoint under real load." },
      { "text" => "2/ The biggest win: batching analytics reads into one query." },
      { "text" => "3/ Full write-up on the blog. Thanks for reading!" }
    ]
  }
)
```

```ruby
# Meta Threads chain with a carousel on the first part
post = client.posts.create(
  content: "Behind the scenes of our summer shoot",
  channels: ["threads"],
  threads: {
    "thread_parts" => [
      { "text" => "Behind the scenes of our summer shoot. A few highlights:", "media_urls" => ["https://example.com/shoot-1.jpg", "https://example.com/shoot-2.jpg"] },
      { "text" => "Day one: scouting locations at sunrise." },
      { "text" => "Day two: the full crew, 14 hours, zero regrets." }
    ]
  }
)
```

On update, passing `x: { "thread_parts" => nil }` clears the thread and reverts the post to single-tweet mode (same for `bluesky`, `mastodon` and `threads`). Only top-level `nil` values are dropped from request bodies, so nested `nil` values like this one are sent as JSON `null`.

Threads posts can also carry a location tag: pass `threads: { "location_id" => "..." }` with an id from `client.locations.search(platform: "threads")` (see Locations below). On a multi-post thread the tag is applied to part 1, and on update `threads: { "location_id" => nil }` clears it. Threads location tagging is currently rolling out; until Meta approves the permissions it is disabled on production and calls return a clear error.

Threads posts can carry a topic too: pass `threads: { "topic_tag" => "Build in public" }`. Unlike a #tag in the text, a topic can hold spaces. 1 to 50 characters, no period and no ampersand; a leading `#` is dropped. On a multi-post thread the topic is applied to part 1, and on update `threads: { "topic_tag" => nil }` removes it.

### X link posts use credits

X bills API posts whose text contains a URL at a premium, and OmniSocials passes that fee through as prepaid credits (20 credits per URL-containing tweet; threads billed per part with a link). When a create targets X and the text contains a URL, the response Hash includes a top-level `"warnings"` array (a sibling of `"data"`):

```ruby
res = client.posts.create(
  content: "Read the full story: https://example.com/post",
  channels: ["x"]
)
(res["warnings"] || []).each do |warning|
  if warning["code"] == "x_url_post_credits"
    puts "#{warning["credits_required"]} credits (balance: #{warning["credits_balance"]})"
  end
end
```

From `enforce_from` (2026-08-14) the balance is checked at publish time, but credits are only deducted after the post successfully publishes (a failed publish is never charged). If the balance can't cover it, only the X target fails (other platforms publish normally); top up in the dashboard under Settings -> Organisation -> Billing -> Credits, then call `posts.retry`. Posts without links and media on X stay free. X statistics use credits too, at X's price (see [X statistics use credits](#x-statistics-use-credits)). `client.credits.get` reads the balance; top-ups are made in the dashboard.

Separately, from 2026-08-14 `posts.create` / `posts.update` / `posts.publish` on X can refuse the request itself, up front, with a `402` and error code `x_credits_insufficient` (`error.details` carries `credits_required`, `credits_balance`, and `credits_reserved`) when reserving this post's cost would push the company's total reserved credits past its balance:

```ruby
begin
  client.posts.create(
    content: "Read the full story: https://example.com/post",
    channels: ["x"],
    scheduled_at: "2026-08-20T09:00:00Z"
  )
rescue OmniSocials::APIError => e
  if e.code == "x_credits_insufficient"
    puts "Not enough reserved credits: #{e.body["error"]["details"]}"
  else
    raise
  end
end
```

Drafts are never gated, and posts scheduled to publish before 2026-08-14 are never gated either.

### Other post operations

```ruby
posts = client.posts.list(status: "scheduled", limit: 50, offset: 0)
post = client.posts.get("123")
client.posts.update("123", scheduled_at: "2026-08-02T10:00:00Z")
client.posts.publish("123")           # publish a draft or scheduled post now
client.posts.retry("123")             # retry only the failed platforms of a failed/warning post
client.posts.delete("123")            # returns nil (204)

# Recent posts fetched live from the connected platforms (including content
# published outside OmniSocials). Requires the analytics:read scope. Video
# records include duration_seconds (whole seconds; TikTok and YouTube today,
# null for images and platforms that don't expose it).
recent = client.posts.recent_platform(limit: 10, platforms: ["instagram", "tiktok"])
```

`retry` re-publishes only the platforms that failed, on the same post; platforms that already succeeded are never posted again. It is asynchronous: a 200 means the retry is queued, so poll `get` for the outcome. Max 3 retries per platform.

These calls answer `409` and change nothing when the post is not in a state for them:

- `post_publishing`: `update` or `delete` while the post is publishing (status `posting`) or a retry publishes one of its channels. Poll `get` until the status is `published`, `warning` or `failed`. An `update` with only `tags` still works.
- `review_required`: changes were requested on the post (`approval_status` `rejected`), so `publish`, or an `update` that would schedule it, is refused. It needs a new review: create it again with `approval_workflow_id`. Saving it as a draft works.
- `retry_in_progress`: `retry` while another retry of the post runs.
- `media_processing`: a media id in `create`, `create_and_publish` or `update` is still processing. Wait until `client.media.get(id)` says `ready`, then send the same request again. A file whose processing failed answers `400 invalid_media`: upload it again.

### Approve or reject a post

```ruby
# Read the step you review first, then name it on the decision.
review = client.posts.get_approval("123")["data"]
step = review["current_step"]

begin
  client.posts.approve("123", step_order: step) # approve the step you reviewed
  # or: reject and stop the workflow (comment optional)
  # client.posts.reject("123", comment: "Wrong CTA link, please fix.", step_order: step)
rescue OmniSocials::APIError => e
  raise unless e.code == "step_changed"

  # Somebody decided since you read it: nothing was decided. Read the approval again.
  puts "The review is on step #{e.body["error"]["current_step_order"]}"
end
```

Only works on a post with `approval_status: "pending"` (`status: "in_approval"`). Both act on behalf of the user who owns the API key, who must be a listed approver for the workflow's CURRENT step. Steps approve in order, so being an approver on a later step is not enough yet (raises a 403 `OmniSocials::PermissionDeniedError`). Approving the last step finalizes the post (`scheduled` or `posting`); rejecting stops the whole workflow immediately, not just the current step.

`step_order:` is optional: the `current_step` of `get_approval`. When the review is on another step now (somebody decided since you read it, or a retried call already went through), nothing is decided and the call raises a 409 `OmniSocials::APIError` with code `step_changed` and `error.current_step_order`, the step the review is on now. Without `step_order:` the call acts on whatever step is current, so a retry after a timeout could approve the next step too.

### Read the approval review

```ruby
review = client.posts.get_approval("123")["data"]
if review["status"] == "rejected" && review["rejection"]
  puts "Rejected by #{review["rejection"]["by"]["name"]}: #{review["rejection"]["reason"]}"
end
review["steps"].each do |step|
  puts "#{step["order"]} #{step["name"]} #{step["status"]}"
end
```

`get_approval` returns the review of a post that went through an approval workflow: `status` (`none`, `pending`, `approved`, `rejected`), the `workflow`, who requested it and when, `current_step` (the step the post waits on, `nil` when the review ended), every step with its approvers and their decisions, the `rejection` (`by`, `reason`, `at`, `step`; `nil` when nobody rejected) and the `comments` thread, oldest first. A post without an approval workflow returns `status: "none"` with empty `steps` and `comments`. Read-only; needs the `posts:read` scope.

## Media

### Upload from a URL (recommended, up to 1GB)

```ruby
media = client.media.upload_from_url(
  url: "https://example.com/promo.mp4",
  name: "promo-august",
  folder: "Campaigns"
)
media_id = media["data"]["id"]
```

Files over 100MB are processed in the background: the response has `media["data"]["status"] == "processing"`; poll `client.media.get(media_id)` until it is `"ready"` before attaching it to a post. When such a file cannot be queued, the call answers `503 processing_unavailable`: send the same request again in a minute.

### Upload a local file (multipart, max 100MB)

```ruby
media = client.media.upload(file: "/path/to/image.jpg", name: "hero-shot")
```

`file` accepts a file path (String or Pathname), an IO (`File.open("...", "rb")`, StringIO), or raw bytes as a binary-encoded String (e.g. from `File.binread`).

Uploading a PDF splits it into image slides (max 20 pages) and returns `slides` plus a `media_ids` array. Pass all of `media_ids`, in order, to `posts.create` to publish the deck as a carousel (on LinkedIn a native swipeable document made from the original PDF file, which is kept so text and links stay intact; an image carousel elsewhere). To keep the PDF as ONE library item instead of one item per page, pass `pdf_mode` = `"document"`: the response then has a single `data` item of type `document` (its page images in `pdf.pages`) and `media_ids` holds that one id, which expands into every page at post time.

Every upload response also includes a `compatibility` block listing any connected platforms that would reject the file.

### Other media operations

```ruby
files = client.media.list(search: "promo", folder_id: "42")
item = client.media.get("1001")
client.media.update("1001", name: "renamed", folder_id: "42")
client.media.update("1001", folder_id: nil)   # move to the root ("All media")
client.media.delete("1001")

# Base64 upload (handy when you have bytes but no URL)
client.media.upload_from_base64(data: b64_string, mime_type: "image/png")

# Preflight compatibility BEFORE uploading
result = client.media.check(url: "https://example.com/huge.mp4")
puts result["summary"] unless result["compatible"]
```

Note the difference between omitting `folder_id` (leave the folder unchanged) and passing `folder_id: nil` (move the file to the root). The same applies to `parent_id` on `folders.update`.

### Large file uploads with a presigned URL

`create_upload_url` mints a one-time upload URL so any environment (a CI job, a sandbox, a script without the SDK) can upload a file without auth headers:

```ruby
grant = client.media.create_upload_url
# grant contains: upload_url, upload_token, expires_in_seconds (600),
# method ("POST"), content_type ("multipart/form-data")
```

POST the file to `grant["upload_url"]` as multipart form data (field name `file`) with no auth headers. The token is single-use and expires after 10 minutes. The response JSON contains the created media item with its `id` (or a `media_ids` array for a PDF).

## Folders

```ruby
folders = client.folders.list
folder = client.folders.create(name: "Campaigns")
sub = client.folders.create(name: "August", parent_id: folder["data"]["id"])
client.folders.update(sub["data"]["id"], name: "August 2026")
client.folders.update(sub["data"]["id"], parent_id: nil)  # move to top level
client.folders.delete(folder["data"]["id"])  # files move to root, subfolders move up
```

## Hashtag Sets

Save reusable hashtag groups and apply them to posts at create time. Uses the `posts:read` / `posts:write` scopes.

```ruby
set = client.hashtag_sets.create(
  name: "Launch",
  hashtags: ["saas", "buildinpublic", "startup"]  # or one string: "#saas #buildinpublic #startup"
)
puts set["data"]["preview"]  # "#saas #buildinpublic #startup"

client.hashtag_sets.list
client.hashtag_sets.get(set["data"]["id"])
client.hashtag_sets.update(set["data"]["id"], hashtags: ["saas", "founder"])  # replaces the full list
client.hashtag_sets.delete(set["data"]["id"])  # returns nil (204)
```

Apply a set when creating a post with `hashtag_set` (the set name, case-insensitive) or `hashtag_set_id`. The set is applied once at create time and tags already in the caption are skipped. `hashtag_placement` is `"caption_append"` (default) or `"first_comment"`, and `hashtag_platforms` restricts the hashtags to a subset of the post's channels. Instagram's 30-hashtag cap returns error code `hashtag_limit_exceeded`.

```ruby
client.posts.create(
  content: "Launch day!",
  channels: ["instagram", "x"],
  scheduled_at: "2026-08-01T09:00:00Z",
  hashtag_set: "Launch",
  hashtag_placement: "first_comment",
  hashtag_platforms: ["instagram"]
)
```

## Post tags

Tags are your workspace's own labels for posts (a hook style, a format, a campaign), to filter posts and compare how each kind does. They never go to a platform. Uses the `posts:read` / `posts:write` scopes; the comparison uses `analytics:read`. A tag is `{ "id", "name", "color", "created_at" }`; names are unique in the workspace (case-insensitive, max 40 characters), at most 200 tags per workspace.

```ruby
tag = client.tags.create(name: "Question", color: "teal")  # color is optional
client.tags.list
client.tags.update(tag["data"]["id"], name: "Question hook")
client.tags.delete(tag["data"]["id"])  # { "data" => { "tag" => ..., "posts_untagged" => 4 } }

# Tag a post: ids or names, a new name becomes a tag (at most 20 per post)
client.posts.create(content: "Would you post this?", channels: ["instagram"], tags: ["Question"])
client.posts.update("1024", tags: ["Question", "Talking head"])  # replaces; tags: nil or [] removes all

# Up to 500 posts at once, published ones included: add, remove or set (replace)
result = client.tags.apply(post_ids: ["1024", "1025"], add: ["Question"], remove: ["Listicle"])
puts result["data"]["updated"], result["data"]["not_found"].inspect

# Filter by tag (an id or name, or an Array: posts with any of them)
client.posts.list(tag: "Question")
client.analytics.overview(period: "30d", tag: ["Question", "Talking head"])

# How each tag did against your normal (default: the last 90 days)
compare = client.analytics.tags(start_date: "2026-08-01", end_date: "2026-10-31")
compare["data"]["tags"].each do |row|
  puts "#{row["tag"]["name"]} #{row["vs_normal"]} #{row["enough_posts"]}"  # vs_normal 0.38 = 38% above
end
```

`analytics.tags` returns `period`, `platform`, `min_posts`, `tags` (comparable tags first, best first; each with `posts`, `measured`, `median_impressions`, `engagement_rate` in percent, `vs_normal` as a fraction, `best_channel` and `enough_posts`), `untagged` (the same numbers for posts without a tag) and `normals` (median impressions per channel). `platform:` keeps one channel's numbers and `min_posts:` (default 5) sets how many measured posts a tag needs before `enough_posts` is true. Every post carries `tags` and `trial_reel` (`{ "strategy" => "MANUAL" | "SS_PERFORMANCE" }` for an Instagram Trial Reel, else `nil`), and so does every entry of `analytics.posts`. Errors: `404 tag_not_found`, `409 tag_exists` (the existing tag is in `e.body["error"]["tag"]`), `409 tag_limit_reached`, `400 invalid_tag_name`, `invalid_tag_color`, `invalid_tags`, `invalid_post_ids`, `too_many_posts`, `too_many_tags`.

## Accounts

```ruby
accounts = client.accounts.list
accounts["data"].each do |account|
  puts "#{account["platform"]}: #{account["username"]} (#{account["status"]})"
  puts "  needs a reconnect: #{account["reauth_reason"]}" if account["needs_reconnect"]
end

account = client.accounts.get("instagram")
```

`status` is `active` or `needs_reconnect` (the token was revoked or expired; Bluesky also when its sign-in could not be renewed). Posts to a `needs_reconnect` account fail until it is reconnected in the OmniSocials app. OmniSocials Connect customer workspaces can also show `pick_pending` (Facebook, Connect customers only: no Page chosen yet).

An X account also carries `x_statistics` (`posts`, `followers`, `post_schedule`, `source`, `billing`, `state`, `paused_reason`): how often OmniSocials reads its X statistics and who pays. `client.accounts.update(account_id, x_statistics: {...})` changes it; see [X statistics use credits](#x-statistics-use-credits).

## Analytics

```ruby
# One post
stats = client.analytics.post("123")

# Up to 100 posts in one request (avoids rate limit trouble when syncing)
bulk = client.analytics.posts(["123", "124", "125"])

# Workspace overview
overview = client.analytics.overview(period: "30d")

# Account-level stats (followers etc.)
accounts = client.analytics.accounts(platform: "instagram")
```

### Best times to post

The response is not wrapped in `data`. `platform`, `timezone`, `basis`, `grid` and `recommendations` sit at the top level.

```ruby
best = client.analytics.best_times(platform: "instagram", timezone: "Europe/Amsterdam")
best["recommendations"].each { |slot| puts "#{slot["day"]} #{slot["time"]} #{slot["score"]}" }
```

### X statistics use credits

X bills every statistics read, and OmniSocials passes X's price on as credits: half a credit per post check (plus half a credit when the tweet has a video or GIF; each part of a thread counts) and 1 credit per follower count. Every X account carries `x_statistics`:

- `posts`: how often each post is checked. `full` (5 checks: about 5 hours, day 1, 3 and 7, and day 30 for posts with 100+ views), `light` (2 checks: about 5 hours and day 7) or `off`.
- `followers`: how often the follower count is read. `daily`, `weekly` or `off`.
- `source` (`account` or `default`), `billing` (`credits`), `state` (`active`, `paused`, `off`) and `paused_reason` (`insufficient_credits` or null).

When the balance reaches 0 the reads pause (`state` `paused`) and start again by themselves after a top-up; the webhook events `x_statistics.paused` and `x_statistics.resumed` say so. `x_statistics.charging` in the answer of `client.credits.get` says whether reads are charged yet and from when.

```ruby
# How often an X account is checked (opt-in scope accounts:write, billing rights)
account = client.accounts.update(
  "1234_x",
  x_statistics: { posts: "light", followers: "daily" } # one key or both
)
puts account["data"]["x_statistics"]["state"]

# "Update now": read one post's X numbers now (scope analytics:read)
fresh = client.analytics.refresh_post(9123)
puts fresh["data"]["credits_used"]

# The balance and what X statistics cost (opt-in scope credits:read, billing rights)
credits = client.credits.get["data"]
puts credits["balance"], credits["x_statistics"]["total_credits_month"]
```

`analytics.refresh_post` costs nothing when the post was already read that day (UTC) and works at most 5 times a post and 100 times an organisation a day. Errors: `402 insufficient_credits`, `409 refresh_not_available` (no published X tweet), `429 refresh_limit`, `502 refresh_failed` (nothing charged). Because it can cost credits, the SDK retries it only after a 429, never after a 5xx or a timeout. `accounts.update` needs the opt-in scope `accounts:write` and billing rights (manage_billing) for the key's creator, sends only the keys you give, and answers `400 validation_error`, `invalid_value` or `not_supported` (not an X account) and `403 insufficient_permission` (no billing rights for the key's creator). `credits.get` needs the opt-in scope `credits:read` and billing rights.

## Locations (Instagram and Threads place tagging)

```ruby
results = client.locations.search("Blue Bottle Coffee Oakland")
location_id = results["data"][0]["id"]
client.locations.validate(location_id)

client.posts.create(
  content: "Great coffee here",
  channels: ["instagram"],
  media_urls: ["https://example.com/latte.jpg"],
  location_id: location_id
)
```

Threads uses its own location ids (a Facebook Place ID is not a Threads location id). Pass `platform: "threads"` and search by keyword, or by `latitude` plus `longitude` instead of `q`; use a result's `id` as `threads.location_id` on a post:

```ruby
results = client.locations.search("Blue Bottle Coffee Oakland", platform: "threads")
# or around a point instead of a keyword:
results = client.locations.search(platform: "threads", latitude: 37.8044, longitude: -122.2712)
threads_location_id = results["locations"][0]["id"]

client.posts.create(
  content: "Great coffee here",
  channels: ["threads"],
  threads: { "location_id" => threads_location_id }
)
```

The Threads response is `{ "locations" => [...] }` (each with nullable `name`, `address`, `city`, `country`, `latitude`, `longitude`) or `{ "error" => { "code", "message" } }` with `code` one of `not_available`, `threads_not_connected`, `threads_reauth_required` (reconnect Threads), or `platform_error`. Threads location tagging is currently rolling out; until Meta approves the permissions it is disabled on production and calls return a clear error.

## Pinterest product tags

Tag products on a Pin so people can shop the items in the image. `client.pinterest.list_products` returns the product Pins of the connected Pinterest account; pass their `pin_id` values (max 24) as `"product_tags"` in the `pinterest` options of the post. Only product Pins of your own account can be tagged; products of other merchants cannot. The tags are added right after the Pin is published. A product that Pinterest refuses never fails the post: the outcome is on the post as `pinterest["product_tags_result"]` (`requested`, `tagged`, `skipped`, `error`).

```ruby
result = client.pinterest.list_products

if result["error"]
  # HTTP 200 without "products": pinterest_not_connected,
  # pinterest_catalog_access_required or platform_error
  warn "#{result["error"]["code"]}: #{result["error"]["message"]}"
else
  product_tags = result["products"].first(3).map { |product| product["pin_id"] }

  client.posts.create(
    content: "Our summer picks",
    channels: ["pinterest"],
    media_urls: ["https://example.com/summer-look.jpg"],
    scheduled_at: "2026-08-01T09:00:00Z",
    pinterest: { "board_id" => "1234567890", "title" => "Summer picks", "product_tags" => product_tags }
  )
end
```

Without `source:` the list reads the Pinterest catalog (with `price`, `currency`, `availability` and `item_id`) when the connection has catalog access, else the account's own Pins. Catalog access is given one time in the OmniSocials composer: Pinterest options, Add products, Connect catalog. `source: "pins"` scans up to 250 Pins per call, so `"products"` can be empty while `"bookmark"` is set; call again with `bookmark: result["bookmark"]`. To check one Pin id or Pin link before you post, call `client.pinterest.validate_product("813744226420795884")`. On `posts.update` the `pinterest` hash replaces the stored one, so leave `"product_tags"` out to remove the tags.

## Inbox

Read and reply to social inbox conversations (DMs, comments, mentions) across connected platforms. Requires an API key with the opt-in `inbox:read` / `inbox:write` scopes. The list endpoints are cursor-paginated (unlike the offset pagination used elsewhere): page while `pagination["has_more"]` is true by passing the previous response's `pagination["next_cursor"]` as `cursor`.

```ruby
conversations = client.inbox.list_conversations(platform: "instagram", unread: true, limit: 20)
conversations["data"].each do |conversation|
  puts "#{conversation["platform"]}: #{conversation["preview"]}"
end

conversation_id = conversations["data"][0]["conversation_id"]
messages = client.inbox.get_messages(conversation_id)
messages["data"].each do |message|
  puts "#{message["direction"]}: #{message["text"]}"  # direction is "incoming" or "outgoing"
end

client.inbox.mark_read(conversation_id)
client.inbox.reply(conversation_id, text: "Thanks for reaching out!")

# Hide or unhide a comment someone left on one of your posts (Facebook,
# Instagram, TikTok, YouTube, Threads). Delete removes it outright (Facebook,
# Instagram, TikTok; YouTube: hide instead), replies under it included.
message_id = messages["data"][0]["id"]
client.inbox.hide(message_id)               # hide
client.inbox.hide(message_id, hide: false)  # unhide
# Delete a comment, or one of your own replies (Facebook, Instagram, TikTok).
client.inbox.delete_message(message_id)

# Like a comment as the Page or account (Facebook, LinkedIn Page, TikTok).
# The returned message carries its "liked" flag.
liked = client.inbox.like(message_id)       # like
client.inbox.like(message_id, like: false)  # unlike
puts liked["data"]["liked"]                 # true
```

`platform` accepts `"instagram"`, `"facebook"`, `"linkedin"`, `"tiktok"`, `"youtube"`, `"x"`, or `"threads"`; `type` accepts `"dm"`, `"comment"`, or `"mention"`. Threads conversations are comments (replies people leave on your Threads posts) and mentions; there are no Threads DMs. Comments can be hidden on Facebook, Instagram, TikTok, YouTube, and Threads (Threads: incoming top-level replies only), and a hidden message keeps its place in the conversation with its `hidden` flag set; `hidden` is `true`/`false` on comments and `nil` on DMs. `liked` is `true`/`false` on Facebook, LinkedIn Page, and TikTok comments (whether the connected account liked it; on Facebook and LinkedIn it reflects likes made through OmniSocials, TikTok also syncs likes made in the TikTok app) and `nil` where the platform has no like through OmniSocials (DMs, Instagram, YouTube, X, Threads). A comment/mention's `post` carries `url` (public link when the platform provides one) and `media_type` (the platform's own label) next to `id`, `caption`, and `thumbnail`. The Threads inbox needs a Threads connection with the reply permission (a 401 `reauth_required` means reconnect Threads; an account connected before 2026-09-14 needs this once). TikTok and YouTube replies are comments only; TikTok replies are capped at 150 characters. Conversation ids are URL-encoded for you, so pass them exactly as returned - LinkedIn ids contain `":"` and `"()"` (e.g. `"linkedin_comment_urn:li:activity:123"`).

`next` hands out the next conversation that still needs a reply (the customer's latest DM with no reply after it, or an unreplied comment/mention that is not hidden), with the whole thread and the post it belongs to, so a reply can be drafted from one call. DMs that can still be answered come first, then Instagram/Facebook DMs whose 24-hour window has closed (`reply_window["open"]` is `false`: answer those from the native app or mark them read), then comments and mentions, oldest first. Replies typed in the native apps count as answers. Only unread items are served by default, so `mark_read` is the durable way to skip one; `exclude` skips conversation ids for the current session only. Always pass `message_id: message["id"]` to `reply` on comment threads: every comment on a post shares one conversation, and without it the reply goes under the newest comment on the post. Pass `include_next: true` to `reply` to get the following item in the same response. `list_conversations(unanswered: true)` gives the same set as a plain list.

```ruby
item = client.inbox.next(platform: "instagram")
while item["data"]
  message = item["data"]["message"]
  puts "#{item["remaining"]} left. #{message["sender"]["username"]}: #{message["text"]}"

  unless item["data"]["reply_window"]["open"]
    # An Instagram/Facebook DM past Meta's 24-hour window: reply would raise
    # 422 outside_messaging_window. Answer it in the app, or skip it.
    client.inbox.mark_read(message["conversation_id"])
    item = client.inbox.next(platform: "instagram")
    next
  end

  reply = client.inbox.reply(
    message["conversation_id"],
    text: "Thanks! DM sent.",
    message_id: message["id"], # the comment being answered, not the newest one
    include_next: true
  )
  item = { "data" => reply["next"], "remaining" => reply["remaining"] || 0 }
end
```

Replying to an X DM costs 2 prepaid credits, debited from the company balance before the send and automatically refunded if the send fails:

```ruby
begin
  client.inbox.reply(conversation_id, text: "On it, thanks!")
rescue OmniSocials::APIError => e
  case e.code
  when "insufficient_credits"
    puts "Not enough credits to send this reply (need 2)."
  when "x_inbox_suspended"
    puts "X inbox is suspended until a top-up."
  else
    raise
  end
end
```

`x_inbox_suspended` fires once a workspace's X inbox has auto-suspended after its credit balance hit zero; topping up and re-enabling it in the dashboard resumes delivery, but DMs that arrived while suspended are not recovered.

## Ads

Boost a published post or create a new ad on Meta, Pinterest, TikTok, LinkedIn, X and Google. Boosts and new ads are drafts: your code writes the draft, and the person who pays sees the amount and starts the ad in OmniSocials from the draft's `review_url`. A key starts and raises spend itself only with the opt-in **Start ads** switch (scope `ads:spend`). Without it `ads.activate`, `ads.activate_multi`, `ads.resume`, `ads.drafts.launch`, a budget raise or any change of a campaign that reached the network through `ads.update`, and the parity calls that switch something on or raise a budget answer `403 start_in_app`, and the error message names the page where the person does it. Google (`api_draft_only` of `ads.capabilities`) always stops at the draft, also with `ads:spend`. `ads.pause` and `ads.delete` stay open, except on the networks in `api_stop_in_app` (Google), where a campaign that reached the network also answers `403 start_in_app`. Only a paused campaign resumes (`409 not_paused`). The calls that start or raise spend repeat the amount (`confirm_budget_amount`) and are not retried after a 5xx or a timeout, only after a 429, because the first attempt may have started the ad: read the campaign or the draft to see what happened.

The `ads:read` and `ads:write` scopes are opt-in: create the API key with **Ads** switched on (Settings, API). `ads:spend` is the **Start ads** switch under it, offered only to a person with `manage_ads`. A key without a scope it needs gets `403 insufficient_scope`. Ad accounts are connected and picked in the OmniSocials dashboard. Budgets are in major units (10 = 10 EUR) in the ad account's currency: a draft whose `budget["currency"]` differs from the attached ad account's currency answers `400 currency_mismatch`. Ads errors may carry `param`, the field at fault: read it from `e.body["error"]["param"]` on the raised `OmniSocials::APIError` (here `"budget.currency"`). Ad account and campaign ids come back as strings (`"51"`); the methods take an id as a string or a number.

### Create an ad (a draft the person starts)

```ruby
caps = client.ads.capabilities
p caps["data"]["create_networks"], caps["data"]["network_states"]

draft = client.ads.drafts.create(
  name: "Autumn sale",
  objective: "traffic",
  platforms: %w[meta linkedin],
  budget: { "amount" => 10, "currency" => "EUR" },
  schedule: { "duration_days" => 7 },
  targeting: { "countries" => %w[NL BE], "automatic_audience" => true },
  ads: [
    {
      "media" => [{ "url" => "https://example.com/sale.jpg", "type" => "image", "width" => 1080, "height" => 1350 }],
      "primary_text" => "30% off everything this week",
      "headline" => "Autumn sale",
      "cta" => "shop_now",
      "link" => "https://example.com/sale"
    }
  ]
)["data"]

# A draft spends nothing. The person checks it and starts it in OmniSocials:
puts "Check and start the ad here: #{draft["review_url"]}"
```

With a key that has `ads:spend`, `client.ads.drafts.launch(draft["group_id"], confirm_budget_amount: 10)` starts the draft after the person agreed to the amount; Google is skipped with code `start_in_app`. Without `ads:spend` the call answers `403 start_in_app`.

A draft needs no ad account; `client.ads.drafts.attach_account(group_id, platform: "meta", ad_account_id: "51")` sets one, and `campaigns[].readiness` says what still stops a network. `client.ads.drafts.update(group_id, ...)` replaces the whole draft (HTTP PUT), so send every field again. On Meta an ad can carry a second upright 9:16 file for Stories and Reels: `"placement_media" => { "stories_reels" => { "url" => ..., "type" => ... } }`.

### Boost a post

```ruby
accounts = client.ads.list_accounts["data"]
meta = accounts.find { |account| account["platform"] == "meta" && account["is_selected"] }

boost = client.ads.boost(
  post_id: 12_345,
  ad_account_id: meta["id"],
  budget: { "type" => "daily", "amount" => 5, "currency" => meta.dig("account_info", "currency") || "EUR" },
  targeting: { "countries" => ["NL"] }
)["data"]

# The boost is a draft: the person starts it in OmniSocials.
puts boost["status"] # "draft"
```

`client.ads.boost_multi` makes one draft boost per ad account (up to 10, the same budget each). `client.ads.suggestions` lists posts that do better than your median, `client.ads.overview` the totals (`totals["spend"]` is `nil` when the campaigns use more than one currency: read `totals_by_currency`, one row per currency), and `client.ads.list`, `get`, `pause` and `delete` manage campaigns. Keyword ideas through the connected Google Ads account: `client.ads.research_keywords(keywords: ["running shoes"], country: "NL")` and `client.ads.keyword_metrics(keywords: [...])`.

### More of the Ads API

Sub-resources cover the rest of the Ads API: `objects` (the tree of an ad account, also campaigns made outside OmniSocials, and their import), `campaign_ads`, `comments`, `targeting`, `audiences`, `lead_forms`, `leads`, `conversions`, `insights`, `reports`, `rules`, `results`, `media`, `previews`, `partnership`, `accounts` (health, finance, settings, people), `reach_frequency`, `studies`, `budget_schedules` and `google`, plus `ads.bulk_status` and `ads.duplicate`. A network without a feature answers `400 not_supported_on_network`; `ads.capabilities` lists `features` and `targeting_types` per network. Every call that switches something on or raises spend needs a key with `ads:spend` (without it, and on Google always, `403 start_in_app`; a rule that switches on or raises a budget: `403 rule_raises_spend`): `objects.update`, `objects.set_status` (switching on), `objects.duplicate`, `bulk_status` (resuming), `campaign_ads.add`, `campaign_ads.set_status` (switching on), `rules.create`, `rules.update`, `rules.undo`, `accounts.update_settings` (a spend cap), `reach_frequency.reserve`, `studies.create` and `budget_schedules.create`. The ones that raise spend take the person's own amount and are not retried after a 5xx or a timeout. Pausing, deleting and archiving stay open, except on Google; a rule that notifies, pauses or lowers a budget works with `ads:write` and never acts on Google.

```ruby
interests = client.ads.targeting.search(ad_account_id: meta["id"], type: "interest", q: "running")["data"]["items"]
# Use the ids in targeting["networks"]["meta"]["include"]["interest"] of a draft.
```

## Webhooks

Subscribe to `post.scheduled`, `post.published`, `post.failed`, `post.approved`, and `post.rejected` events. `post.approved` fires when the last step of a post's approval workflow is approved, `post.rejected` when an approver rejects the post (it will not publish). These two carry `data["approval"]` with `status`, `decided_by` (the approver's user id) and `reason` (`nil` on `post.approved`), and an empty `data["targets"]`. `ad.status_changed` fires when an ad campaign changes status (for example `pending_review` to `active` or `rejected`); its `data` is the campaign, not a post: `campaign_id`, `workspace_id`, `name`, `platform`, `campaign_type`, `status`, `previous_status`, `external_campaign_id` and `budget`. The other ads events are `ad.created`, `ad.updated`, `ad.review`, `ad.delivery_issue`, `campaign.created`, `campaign.updated`, `campaign.budget`, `lead.received`, `ads.sync_failed`, `ads.sync_recovered`, `ads.initial_sync_completed` and `ad_rule.triggered`. Subscribing to `ad.status_changed` or any other Ads event (`ad.*`, `campaign.*`, `lead.*`, `ads.*`, `ad_rule.*`) needs the `ads:read` scope on the key and `access_ads` for its person (`403 insufficient_scope` / `insufficient_permission`). `x_statistics.paused` and `x_statistics.resumed` fire when the organisation's X statistics stop at 0 credits or start again after a top-up, one delivery per workspace with X; `data` is `{ workspace_id, account_id, reason }` (`reason` is `insufficient_credits` or `credits_added`).

```ruby
webhook = client.webhooks.create(
  url: "https://example.com/hooks/omnisocials",
  events: ["post.published", "post.failed"]
)
secret = webhook["data"]["secret"]  # only shown once, store it

client.webhooks.list
client.webhooks.get(webhook["data"]["id"])
client.webhooks.update(webhook["data"]["id"], is_active: false)
client.webhooks.rotate_secret(webhook["data"]["id"])  # new secret, shown once; the old one signs for 24 hours more
client.webhooks.delete(webhook["data"]["id"])
```

Every webhook carries `workspace_id`. `list` and `get` also return the organisation-wide webhooks of the key's organisation (`workspace_id` `nil`, made in the OmniSocials dashboard; they receive the events of every workspace), and `update`, `delete` and `rotate_secret` work on them too. Webhooks you create through the API belong to the key's workspace. When the person behind a webhook loses access to the organisation or workspace, OmniSocials switches the webhook off: `is_active` is `false` and `last_failure["error"]` says why. `update(id, is_active: true)` switches it on again.

### Verifying webhook signatures (Rails example)

Every delivery is signed with HMAC-SHA256. The `X-OmniSocials-Signature` header has the form `t=<unix>,v1=<hex>`, signed over `"{timestamp}.{raw_body}"`. Use `OmniSocials::Webhooks.verify` with the raw request body (do not parse it first):

```ruby
class OmnisocialsWebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token

  def create
    payload = request.body.read  # raw body, exactly as received
    signature = request.headers["X-OmniSocials-Signature"]

    begin
      event = OmniSocials::Webhooks.verify(
        payload: payload,
        signature: signature,
        secret: ENV.fetch("OMNISOCIALS_WEBHOOK_SECRET"),
        tolerance: 300
      )
    rescue OmniSocials::WebhookVerificationError
      return head :bad_request
    end

    if event["type"] == "post.published"
      event["data"]["targets"].each do |target|
        Rails.logger.info "#{target["platform"]} #{target["status"]} #{target["native_post_id"]}"
      end
    elsif event["type"] == "post.rejected"
      Rails.logger.info "Rejected: #{event["data"]["post_id"]} #{event["data"]["approval"]["reason"]}"
    end

    head :ok
  end
end
```

### Verifying webhook signatures (plain Rack)

```ruby
# config.ru
require "omnisocials"

app = lambda do |env|
  request = Rack::Request.new(env)
  payload = request.body.read
  signature = env["HTTP_X_OMNISOCIALS_SIGNATURE"]

  begin
    event = OmniSocials::Webhooks.verify(
      payload: payload,
      signature: signature,
      secret: ENV.fetch("OMNISOCIALS_WEBHOOK_SECRET")
    )
  rescue OmniSocials::WebhookVerificationError
    next [400, { "content-type" => "application/json" }, ['{"error":"invalid signature"}']]
  end

  # handle event["type"] ...
  [200, { "content-type" => "application/json" }, ['{"ok":true}']]
end

run app
```

`OmniSocials::Webhooks.verify` uses a constant-time comparison, rejects timestamps older than `tolerance` seconds (default 300) to block replays, and returns the parsed event Hash on success. Respond with any 2xx within 10 seconds to acknowledge; deliveries are retried up to 3 times.

### Rotate the secret without missing deliveries

For 24 hours after `rotate_secret`, every delivery carries two headers: `X-OmniSocials-Signature`, signed with the new secret, and `X-OmniSocials-Signature-Previous`, signed with the old secret (same format, same timestamp and body). Verify the first with the new secret and, when that fails, the second with the old one:

```ruby
def verify_delivery(payload, headers)
  OmniSocials::Webhooks.verify(
    payload: payload,
    signature: headers["X-OmniSocials-Signature"],
    secret: ENV.fetch("OMNISOCIALS_WEBHOOK_SECRET") # the new secret
  )
rescue OmniSocials::WebhookVerificationError
  previous = headers["X-OmniSocials-Signature-Previous"]
  raise if previous.nil?

  OmniSocials::Webhooks.verify(
    payload: payload,
    signature: previous,
    secret: ENV.fetch("OMNISOCIALS_WEBHOOK_SECRET_OLD") # the old secret
  )
end
```

Rotating again within the 24 hours replaces the previous secret with the one you just rotated out.

## Limits and feature requests

`client.limits.list` lists what OmniSocials cannot do, why (`says`) and what to do instead (`instead`): platform rules, features not built yet, features that work in the OmniSocials app only. Read it before you tell a person that something is not possible. When the person still wants a `requestable` entry, send a feature request with its `limit_id`. The request is stored for the person who owns the key; they see it in OmniSocials (Settings, Request a feature) and get an email when its status changes. Works with every key, no scope needed.

```ruby
limits = client.limits.list(platform: "telegram") # area: "posts" | "inbox" | ...
limits["data"].each do |limit|
  puts [limit["id"], limit["says"], limit["instead"], limit["requestable"]].inspect
end

begin
  result = client.feature_requests.create(
    summary: "Post our daily update to the Announcements topic of our Telegram group, not to the whole group.",
    platform: "telegram",
    limit_id: "telegram.forum_topics"
  )
  # "created" (new), "voted" (added a vote to your organisation's open request)
  # or "already_requested" (you asked before; data is that request)
  puts result["outcome"], result["data"]["id"], result["data"]["status"]
rescue OmniSocials::APIError => e
  raise unless e.code == "not_requestable"

  # A platform rule or a choice of OmniSocials: nothing was stored.
  limit = e.body["error"]["limit"]
  puts limit["says"], limit["instead"]
end

mine = client.feature_requests.list # newest first, at most 50
one = client.feature_requests.get(mine["data"].first["id"]) # status, team_answer, team_replies
```

A limit is `{ "id", "kind", "kind_label", "area", "platforms", "title", "says", "instead", "requestable" }`; `kind` is `platform`, `by_design`, `not_built`, `beta`, `dashboard_only` or `needs_setup`, and `requestable` is false for `platform` and `by_design`. `limits.list` also returns `kinds` (a label per kind). A request carries `status` (`open`, `in_progress`, `completed`, `declined`), `votes_count`, `team_answer` and `team_replies`. `summary:` is 10 to 1000 characters (what the person wants to do and why), `title:` at most 120 (made from the summary when left out); `area:` is one of posts, media, inbox, analytics, automations, accounts, ads, team, other. Errors: `400 invalid_summary` / `invalid_title` / `invalid_platform` / `invalid_area` / `unknown_limit`, `409 not_requestable` (the entry is in `e.body["error"]["limit"]`), `429 too_many_requests` (10 an hour per person), and `400 invalid_id` / `404 not_found` on `get`.

## Error handling

Non-2xx responses raise typed exceptions with `status`, `code`, `message`, and the parsed `body`:

```ruby
begin
  client.posts.get("does-not-exist")
rescue OmniSocials::NotFoundError => e
  puts "Gone: #{e.code} #{e.message}"
rescue OmniSocials::RateLimitError => e
  puts "Slow down, retry in #{e.retry_after}s"
rescue OmniSocials::ValidationError => e
  puts "Bad request: #{e.body}"
rescue OmniSocials::AuthenticationError
  puts "Check your API key"
rescue OmniSocials::APIConnectionError
  puts "Network problem"
rescue OmniSocials::APIError => e
  puts "API error: #{e.status} #{e.message}"
end
```

The full hierarchy: `OmniSocials::Error` is the base; `OmniSocials::APIError` covers all HTTP errors with subclasses `AuthenticationError` (401), `PermissionDeniedError` (403), `NotFoundError` (404), `ValidationError` (400/422), `RateLimitError` (429, with `#retry_after`), and `ServerError` (5xx); `APIConnectionError` covers network failures; `WebhookVerificationError` covers signature failures.

## Rate limits

The API allows **100 requests per minute** per API key. Every response includes `X-RateLimit-Limit`, `X-RateLimit-Remaining`, and `X-RateLimit-Reset` headers. On 429 the SDK automatically waits for the `Retry-After` value and retries. When syncing analytics for many posts, prefer the bulk `client.analytics.posts([...])` endpoint (100 posts per request) over per-post calls.

## Retries and timeouts

The SDK automatically retries on 429, 5xx, and connection errors with exponential backoff (0.5s, 1s, 2s, with jitter), honoring the `Retry-After` header when present. Other 4xx errors are never retried. The ads calls that start or raise spend retry a 429 only (see [Ads](#ads)). Defaults: 2 retries, 30 second timeout. Both are configurable:

```ruby
client = OmniSocials::Client.new(
  api_key: "omsk_live_...",
  timeout: 60,        # seconds
  max_retries: 5,     # retries after the first attempt
  base_url: "https://api.omnisocials.com/v1"  # override for testing
)
```

## More

- Full API reference and guides: [https://docs.omnisocials.com](https://docs.omnisocials.com)
- MCP server for AI agents: `npx -y @omnisocials/mcp-server`
- Agent skills CLI: `npx skills add OmniSocials/omnisocials-agent-skills`

## License

MIT
