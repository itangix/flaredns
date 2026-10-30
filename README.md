# flaredns.pl

[English](README.en.md)

Cloudflare DNS 记录批量管理脚本：列出区域 / 列出、新增、修改、删除 DNS 记录。

单文件 Perl 脚本，通过 Cloudflare API v4 操作，依赖 `curl`。

## 依赖

- Perl（核心模块 `JSON::PP`、`File::Temp`、`Getopt::Long`）
- `curl`

## 配置

```sh
export CF_API_TOKEN="xxx"
```

Token 需要的权限：

- `Zone:Zone:Read`
- `Zone:DNS:Edit`

## 用法

```sh
flaredns.pl [选项] 内容...
```

动作五选一，不给出则显示帮助：

| 选项 | 说明 |
| --- | --- |
| `-L, --list` | 列出匹配的记录 |
| `--list-zones` | 列出账号下所有区域（无需 `--zone`） |
| `-A, --add` | 为每个内容各新增一条记录（名称由 `-p` 前缀 + zone 生成，类型默认 A） |
| `-E, --edit` | 改写匹配记录的 content（类型不变） |
| `-D, --delete` | 删除匹配记录；给出内容时仅删除 content 在其中者 |

选项：

| 选项 | 说明 |
| --- | --- |
| `-z, --zone NAME` | 要操作的 Zone 域名（`--list-zones` 时无需） |
| `-t, --type TYPE` | 只处理该类型的记录（如 A、CNAME，大小写不敏感） |
| `-p, --prefix STR` | 名称前缀；也用于 `--add` 生成记录名称（自动补 zone） |
| `-s, --suffix STR` | 名称后缀（大小写不敏感），末尾不含 zone 时自动补全 |
| `-r, --regex RE` | 名称正则（大小写不敏感） |
| `-n, --dry-run` | 只预览，不实际调用写接口 |
| `--comment [文本]` | 列出时显示注释；`--add` / `--edit` 时写入该文本 |
| `--tags LIST` | 逗号分隔的标签，用于 `--add` / `--edit` 写入 |
| `-h, --help` | 显示帮助 |

`-p` / `-s` / `-r` 三选一；都不给则匹配全部。

## 示例

```sh
# 列出账号下所有区域
flaredns.pl --list-zones

# 列出 .web.example.com 下所有记录
flaredns.pl -z example.com -L -s .web

# 新增 api.example.com A 1.1.1.1
flaredns.pl -z example.com -A -p api -t A 1.1.1.1

# 把 web 前缀记录的 content 改为 1.1.1.1
flaredns.pl -z example.com -E -p web 1.1.1.1

# 删除 web 前缀且 content 为 1.1.1.1 的记录
flaredns.pl -z example.com -D -p web 1.1.1.1
```

## 单字段记录

这些类型的 content 直接写单个值：

| 类型 | content |
| --- | --- |
| A | IPv4 地址 |
| AAAA | IPv6 地址 |
| CNAME | 目标域名 |
| TXT | 文本 |
| NS | 名称服务器 |
| PTR | 目标域名 |
| SPF | 策略文本（已弃用，建议用 TXT） |

## 多字段记录

下列类型的 content 按空格分隔，脚本会转成 Cloudflare 需要的 `data`（MX 用 `priority` + `content`）：

| 类型 | content 格式 |
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

示例：

```sh
# SRV
flaredns.pl -z example.com -A -p _sip._tcp -t SRV "10 5 5060 sip.example.com"

# MX（根记录）
flaredns.pl -z example.com -A -p example.com -t MX "10 mail.example.com"

# CAA（根记录）
flaredns.pl -z example.com -A -p example.com -t CAA '0 issue "letsencrypt.org"'
```

`--list` / `--edit` / `--delete` 同样支持这些类型；删除按解析后的字段匹配。

列表中的记录名以 FQDN 显示，末尾带 `.`。

## 许可证

[MIT](LICENSE)
