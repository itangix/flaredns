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

## Single-field records

For these types, `content` is a single value:

| Type | `content` |
| --- | --- |
| A | IPv4 address |
| AAAA | IPv6 address |
| CNAME | target hostname |
| TXT | text |
| NS | nameserver |
| PTR | target hostname |
| SPF | policy text (deprecated; use TXT) |

## Multi-field records

For the types below, write `content` as space-separated fields; the script converts it to the `data` object Cloudflare expects (MX uses `priority` + `content`):

| Type | `content` format |
| --- | --- |
| MX | `priority target` |
| SRV | `priority weight port target` |
| URI | `priority weight target` |
| SVCB / HTTPS | `priority target value` |
| CAA | `flags tag value` |
| TLSA / SMIMEA | `usage selector matching_type certificate` |
| SSHFP | `algorithm type fingerprint` |
| DS | `key_tag algorithm digest_type digest` |
| DNSKEY | `flags protocol algorithm public_key` |
| CERT | `type key_tag algorithm certificate` |
| NAPTR | `order preference flags service regexp replacement` |

Examples:

```sh
# SRV
flaredns.pl -z example.com -A -p _sip._tcp -t SRV "10 5 5060 sip.example.com"

# MX (apex)
flaredns.pl -z example.com -A -p example.com -t MX "10 mail.example.com"

# CAA (apex)
flaredns.pl -z example.com -A -p example.com -t CAA '0 issue "letsencrypt.org"'
```

`--list` / `--edit` / `--delete` also support these types; deletes match on the parsed fields.

Record names are shown as FQDN with a trailing `.`.

## License

[MIT](LICENSE)
