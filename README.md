# flaredns.pl

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

## 许可证

[MIT](LICENSE)
