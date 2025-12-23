# Authenticated Bulk Downloader (aria2c)

A Bash script for bulk downloading files from the private dashboard of `data.infingame.com`.

The script authenticates using a CSRF token and cookies, iterates through all available pages, collects download links, and downloads files in parallel using **aria2c** with resume support.

---

## Requirements

The following tools must be installed:

* `bash`
* `curl`
* `aria2`
* `grep`, `sed`, `awk`, `find`, `sort`, `uniq`, `wc`, `tr`

### Ubuntu / Debian

```bash
sudo apt update
sudo apt install -y curl aria2
```

---

## Installation

Clone the repository and make the script executable:

```bash
git clone <your-repo-url>
cd <repo-directory>
chmod +x download.sh
```

---

## Configuration

Open `download.sh` and configure credentials:

```bash
USERNAME='your_username'
PASSWORD='your_password'
```

### Optional Settings

These can be adjusted inside the script:

| Variable   | Description                               |
| ---------- | ----------------------------------------- |
| `OUTDIR`   | Directory where files will be downloaded  |
| `JOBS`     | Number of parallel downloads (`aria2 -j`) |
| `SPLIT`    | Connections per file (`aria2 -s`)         |
| `MAX_CONN` | Max connections per server (`aria2 -x`)   |
| `CONTINUE` | Resume downloads (`1 = enabled`)          |

---

## Usage

Run the script:

```bash
./download.sh
```

---

## How It Works

* Fetches the login page and extracts the CSRF token
* Performs authenticated login using cookies
* Verifies that a valid session was created
* Detects the total number of available pages
* Collects all download IDs from each page
* Deduplicates download links
* Starts parallel downloads using `aria2c`
* Tracks progress by counting downloaded files

You can safely stop the script and run it again — unfinished downloads will resume automatically.

---

## Output

* Downloaded files are saved to the directory defined by `OUTDIR`
* Temporary HTML pages are stored in `debug_html/` for debugging
* Incomplete downloads will have `.aria2` extensions

---

## Troubleshooting

### Failed to retrieve CSRF token

The login page structure may have changed.

```bash
debug_html/login_fail.html
```

### Login failed (no session cookie)

Invalid credentials or updated authentication logic.

```bash
debug_html/post_login_fail.html
```

### No files found

The page structure or download links may have changed.

```bash
debug_html/page1_noids.html
```

---

## Security Notes

* **Do NOT commit your username or password to the repository**
* Credentials are used only at runtime
* Cookies are stored locally and reused only during execution

---

## License

Licensed under the **Apache License, Version 2.0**.

You may use, modify, and distribute this software, including for commercial purposes, under the terms of the license.

See the `LICENSE` file for details.
