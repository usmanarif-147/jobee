# 13 — File Storage (Media Service)

The Media Service is the gatekeeper for object storage. **No other service writes to or reads from S3 directly.** They go through Media Service to upload, download, or delete files.

This centralizes auth checks, virus scanning, audit logging, and lifecycle policies in one place.

## What we store as files

| Type | Examples | Where |
|---|---|---|
| Resumes | PDF, DOCX | S3 bucket `resumes` |
| Chat attachments | doc, png, jpg, jpeg, webp, audio, video, csv, md | S3 bucket `chat-files` |
| Generated reports | PDF, CSV | S3 bucket `reports` |
| Company logos / banners | png, jpg, webp | S3 bucket `company-assets` (also CDN-cached) |
| Profile pictures | png, jpg, webp | S3 bucket `avatars` (CDN-cached) |

**Local dev:** all of the above live in MinIO (S3-compatible, runs as a Docker container).
**Production:** AWS S3 (or Cloudflare R2 — same API, no egress fees).

## Why object storage, not the filesystem

- Filesystems don't survive container restarts in K8s
- Filesystems don't replicate across multiple servers
- Object storage is the only sane choice once you have more than one app instance

## Direct uploads (the right way)

Files do **not** flow through our app servers. The flow:

1. **Client → Media Service:** "I want to upload a 2MB PDF named resume.pdf"
2. **Media Service:** validates (size, mime, user permissions), generates a **presigned PUT URL** for S3, inserts a row in `attachments` with `scan_status=pending`, returns the upload URL + the file ID
3. **Client → S3 directly:** uploads via the presigned URL
4. **Client → Media Service:** "Upload done, file ID X is ready"
5. **Media Service:** publishes `FileUploaded` event to Kafka topic `media.files`
6. **Virus scan worker** consumes `FileUploaded`, runs ClamAV, publishes `FileScanClean` or `FileScanInfected`
7. **Other services** (e.g., Resume Parser) listen for `FileScanClean` before processing
8. **Client → Jobs Service:** "Attach file ID X to my application"

This pattern:
- Saves our bandwidth
- Saves our memory (no buffering)
- Lets clients show real upload progress
- Coordinates virus scanning before the file is ever served to other users

## File records in DB

Every uploaded file has a row in `attachments` (chat) or a column reference (resume on `applications`):

| Column | Purpose |
|---|---|
| `id` (uuid) | App-side file ID |
| `s3_key` | Path in the bucket |
| `mime_type` | Validated mime |
| `size_bytes` | Validated size |
| `original_name` | What the user named it |
| `owner_id` | Who uploaded it |
| `scan_status` | `pending` / `clean` / `infected` |
| `created_at` | Timestamp |

## Validation

**Server-side, always**:

- Mime type (don't trust client header — sniff it with `finfo`)
- Size limit (e.g., 10MB resumes, 50MB chat files, 5MB images)
- Filename sanitization (strip path components, weird Unicode)

Reject if any check fails before issuing the presigned URL.

## Virus scanning

Files from untrusted users → we must scan.

**Tool:** ClamAV running as a sidecar container. The flow:

1. After client upload completes, an "S3 ObjectCreated" event hits our queue
2. A worker downloads the file, pipes it to ClamAV
3. If clean → mark `scan_status = clean`, file becomes available
4. If infected → mark `scan_status = infected`, delete from S3, notify owner

Files with `scan_status != 'clean'` are **never served** to other users. The client sees a "Scanning…" state until the scan finishes (usually <5 seconds).

## Serving files (presigned download URLs)

Files are **never publicly readable**. To serve a file:

1. Client requests the file (e.g., `GET /media/{id}/download`)
2. Media Service checks: is this user allowed to see this file? (calls Identity / Companies / Jobs Service depending on context)
3. If yes, generates a **presigned GET URL** (5-minute TTL)
4. Returns 302 redirect to the presigned URL
5. Client downloads directly from S3
6. Media Service logs the access for audit

For images that need to be embedded (logos, avatars) we use a **public-read CDN** path with cache headers. That's the only category that's public.

## CDN

Images served to public pages (job listings, company profiles) go through Cloudflare's CDN with long `Cache-Control` (e.g., `public, max-age=31536000, immutable`). Filename includes a content hash so we can invalidate cleanly by changing the URL.

Resumes and chat files are **never** CDN-cached — they're private.

## Image transformations

Don't store multiple sizes of every image. Use a transformation service:

- **Cloudflare Images** (cheap, simple), or
- **ImgIX**, or
- A lightweight self-hosted **imgproxy** behind the CDN

URL like `cdn.job-hunter.com/avatar/{hash}?w=128` returns a 128px crop without us pre-generating it.

## Lifecycle policies

S3 lifecycle rules (no app code needed):

- Resumes: keep forever (recruiter compliance)
- Chat attachments: keep 2 years, then delete
- Reports: keep 1 year, then delete
- "Pending scan" files older than 24 hours: delete (orphans)

## Failure modes

| Failure | Mitigation |
|---|---|
| Client crashes mid-upload | The presigned URL still works for its TTL window; client retries. Orphan files are cleaned by the lifecycle policy. |
| ClamAV crashes | Files stay in `scan_status=pending`; queue retries scan |
| User deletes account | Background job finds all their `attachments` rows and deletes from S3 + DB |

## Security gotchas

- **Path traversal**: never let user input become an S3 key directly; always prefix with `users/{id}/...` and use UUIDs
- **MIME spoofing**: a `.pdf` file might actually be HTML; sniff content
- **SSRF via image URLs**: if we ever fetch images from URLs the user supplies, validate the URL doesn't point to internal IPs
- **Hot-linking**: presigned URLs prevent random sharing; CDN images are intentionally shareable
