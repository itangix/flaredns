# flaredns.pl

[中文](README.md)

Batch manage Cloudflare DNS records: list zones / list, add, edit, delete DNS records.

A single-file Perl script using the Cloudflare API v4. Requires `curl`.

## Requirements

- Perl (core modules `JSON::PP`, `File::Temp`, `Getopt::Long`)
- `curl`

## Configuration

```sh
export CF_API_TOKEN="xxx"
```

Token permissions:

- `Zone:Zone:Read`
- `Zone:DNS:Edit`

## Usage

```sh
flaredns.pl [options] content...
```

Pick exactly one action. With none given, the help is shown:

| Option | Description |
| --- | --- |
| `-L, --list` | List matching records |
| `--list-zones` | List all zones in the account (no `--zone` needed) |
| `-A, --add` | Add one record per content (name = `-p` prefix + zone, type defaults to A) |
| `-E, --edit` | Rewrite the content of matching records (type unchanged) |
| `-D, --delete` | Delete matching records; with content given, only those whose content matches |

Options:

| Option | Description |
| --- | --- |
| `-z, --zone NAME` | Zone to operate on (not needed for `--list-zones`) |
| `-t, --type TYPE` | Only handle records of this type (e.g. A, CNAME; case-insensitive) |
| `-p, --prefix STR` | Name prefix; also used by `--add` to build the record name (zone appended automatically) |
| `-s, --suffix STR` | Name suffix (case-insensitive); zone appended if missing |
| `-r, --regex RE` | Name regex (case-insensitive) |
| `-n, --dry-run` | Preview only; do not call write endpoints |
| `--comment [text]` | Show comments when listing; write the text on `--add` / `--edit` |
| `--tags LIST` | Comma-separated tags, written on `--add` / `--edit` |
| `-h, --help` | Show help |

Choose one of `-p` / `-s` / `-r`; omitting all matches everything.

## Examples

```sh
# List all zones in the account
flaredns.pl --list-zones

# List all records under .web.example.com
flaredns.pl -z example.com -L -s .web

# Add api.example.com A 1.1.1.1
flaredns.pl -z example.com -A -p api -t A 1.1.1.1

# Change the content of web-prefixed records to 1.1.1.1
flaredns.pl -z example.com -E -p web 1.1.1.1

# Delete web-prefixed records whose content is 1.1.1.1
flaredns.pl -z example.com -D -p web 1.1.1.1
```

## License

[MIT](LICENSE)
