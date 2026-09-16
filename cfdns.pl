#!/usr/bin/env perl
#
# Cloudflare DNS 记录批量管理：列出 / 新增 / 修改 / 删除
#
use strict;
use warnings;
use JSON::PP;
use File::Temp qw(tempfile);
use Getopt::Long;

my $tty       = -t STDOUT;
my $C_NAME    = $tty ? "\e[34m" : "";   # 深蓝
my $C_TYPE    = $tty ? "\e[35m" : "";   # 紫
my $C_CONTENT = $tty ? "\e[37m" : "";   # 白
my $C_TTL     = $tty ? "\e[32m" : "";   # 绿
my $C_OFF     = $tty ? "\e[0m"  : "";
my $SEP       = "—" x 40;

sub ttl_str {
    my $ttl = shift;
    return "Auto" if !defined $ttl || $ttl == 1;
    return "${ttl}s" if $ttl < 60;
    my ($m, $s) = (int($ttl / 60), $ttl % 60);
    return "${m}m" . ($s ? "${s}s" : "") if $m < 60;
    my ($h, $mm) = (int($m / 60), $m % 60);
    return "${h}h" . ($mm ? "${mm}m" : "") if $h < 24;
    my ($d, $hh) = (int($h / 24), $h % 24);
    return "${d}d" . ($hh ? "${hh}h" : "");
}

my $dry_run = 0;
my $help    = 0;

my $zone_name;
my ($list, $add, $edit, $delete, $list_zones);
my $suffix;
my $regex;
my $type;
my $prefix;
my $comment_opt;
my $tags_str;

GetOptions(
    'dry-run|n'    => \$dry_run,
    'help|h'       => \$help,
    'zone|z=s'     => \$zone_name,
    'list|L'       => \$list,
    'list-zones'   => \$list_zones,
    'add|A'        => \$add,
    'edit|E'       => \$edit,
    'delete|D'     => \$delete,
    'type|t=s'     => \$type,
    'prefix|p=s'   => \$prefix,
    'suffix|s=s'   => \$suffix,
    'regex|r=s'    => \$regex,
    'comment:s'    => \$comment_opt,
    'tags=s'       => \$tags_str,
) or die "用法: $0 [选项] 内容...（--help 查看帮助）\n";

my $usage = <<"USAGE";
用法: $0 [选项] 内容...

动作（五选一，不给出则显示本帮助）:
  -L, --list            列出匹配的记录
      --list-zones      列出账号下所有区域（无需 --zone）
  -A, --add             为每个内容各新增一条记录
                        （名称由 -p 前缀 + zone 生成，类型默认 A）
  -E, --edit            改写匹配记录的 content（类型不变）
                        内容只有一个时全部设为它，否则与匹配记录一一对应
                        省略内容时配合 --tags/--comment 可只写标签/注释
  -D, --delete          删除匹配记录；给出内容时仅删除 content 在其中者

选项:
  -z, --zone NAME     要操作的 Zone 域名（--list-zones 时无需）
  -t, --type TYPE     只处理该类型的记录（如 A、CNAME，大小写不敏感）
  -p, --prefix STR    名称前缀；也用于 --add 生成记录名称（自动补 zone）
  -s, --suffix STR    名称后缀（大小写不敏感），末尾不含 zone 时自动补全
  -r, --regex RE      名称正则（大小写不敏感）
                      -p / -s / -r 三选一；都不给则匹配全部
  -n, --dry-run       只预览，不实际调用写接口
      --comment [文本] 列出时显示注释；--add / --edit 时写入该文本
      --tags LIST     逗号分隔的标签，用于 --add / --edit 写入
  -h, --help          显示本帮助

环境变量:
  CF_API_TOKEN     必填。Cloudflare API Token
                   需要权限: Zone:Zone:Read + Zone:DNS:Edit

示例:
  export CF_API_TOKEN="xxx"

  # 列出账号下所有区域
  $0 --list-zones

  # 列出 .web.example.com 下所有记录
  $0 -z example.com -L -s .web

  # 新增 api.example.com A 1.1.1.1
  $0 -z example.com -A -p api -t A 1.1.1.1

  # 把 web 前缀记录的 content 改为 1.1.1.1
  $0 -z example.com -E -p web 1.1.1.1

  # 删除 web 前缀且 content 为 1.1.1.1 的记录
  $0 -z example.com -D -p web 1.1.1.1
USAGE

if ($help) { print $usage; exit 0; }

my $n_actions = grep { $_ } $list, $list_zones, $add, $edit, $delete;
if (!$n_actions) { print $usage; exit 0; }
die "动作只能选一个（-L / --list-zones / -A / -E / -D）\n" if $n_actions > 1;

my $action = $list ? 'list' : $list_zones ? 'list-zones'
    : $add ? 'add' : $edit ? 'edit' : 'delete';

my @contents = @ARGV;

# --tags 逗号分隔
my @tags = defined $tags_str ? grep { length } split /\s*,\s*/, $tags_str : ();

# --comment：列出时显示；add/edit 时写入（有文本才写）
my $show_comment  = defined $comment_opt;
my $write_comment = defined $comment_opt && length $comment_opt;

die "缺少必填参数 --zone（用 --help 查看用法）\n"
    unless $action eq 'list-zones' || (defined $zone_name && length $zone_name);
die "-p / -s / -r 只能选一个（用 --help 查看用法）\n"
    if (grep { defined && length } $prefix, $suffix, $regex) > 1;
die "匹配规则不能为空\n"
    if grep { defined && !length } $suffix, $regex, $prefix, $type;

die "--$action 需要内容参数\n"
    if $action eq 'add' && !@contents;
die "--edit 需要内容参数或 --tags/--comment\n"
    if $action eq 'edit' && !@contents && !defined $tags_str && !$write_comment;

die "--add 需要 -p|--prefix 来生成记录名称\n"
    if $action eq 'add' && !(defined $prefix && length $prefix);

# --suffix 末尾不是 zone 时自动补全
if (defined $zone_name && defined $suffix && $suffix !~ /\Q$zone_name\E$/i) {
    $suffix .= '.' unless $suffix =~ /\.$/;
    $suffix .= $zone_name;
}

# --add 的名称 = 前缀 + zone
my $add_name;
my $add_type = defined $type ? uc $type : 'A';
if ($action eq 'add') {
    $add_name = $prefix;
    $add_name .= '.' unless $add_name =~ /\.$/;
    $add_name .= $zone_name unless $add_name =~ /\Q$zone_name\E$/i;
}

my $api_token = $ENV{CF_API_TOKEN}
    or die "请设置环境变量 CF_API_TOKEN（用 --help 查看用法）\n";

my $api_base = 'https://api.cloudflare.com/client/v4';

# curl 后端
sub api_request {
    my ($method, $path, $body) = @_;
    my $url = $api_base . $path;

    my @cmd = (
        'curl', '-sS', '-X', $method, $url,
        '-H', 'Authorization: Bearer ' . $api_token,
        '-H', 'Content-Type: application/json',
        '-w', "\n%{http_code}",
    );

    my $tmpfile;
    if ($body) {
        my $json = JSON::PP->new->canonical->encode($body);
        my ($fh, $name) = tempfile();
        print $fh $json;
        close $fh;
        $tmpfile = $name;
        push @cmd, ('--data-binary', '@' . $tmpfile);
    }

    open my $pipe, '-|', @cmd or die "无法启动 curl: $!";
    local $/;
    my $out = <$pipe>;
    close $pipe;
    unlink $tmpfile if $tmpfile;

    my ($content, $status) = $out =~ /^(.*)\n(\d+)\s*$/s;
    die "curl $method $url 失败: HTTP " . ($status // '???') . "\n$content\n"
        unless $status && $status =~ /^2\d\d$/;

    my $data = JSON::PP->new->decode($content);
    if (!$data->{success}) {
        my $errors = join ', ', map { $_->{message} } @{ $data->{errors} || [] };
        die "API $method $path 失败: $errors\n";
    }
    return $data->{result};
}

# 列出所有区域
if ($action eq 'list-zones') {
    my @zones;
    my $page = 1;
    while (1) {
        my $res = api_request('GET', "/zones?per_page=50&page=$page");
        push @zones, @$res;
        last if @$res < 50;
        $page++;
    }
    print "共 " . scalar(@zones) . " 个区域\n";
    print "$SEP\n";
    for my $z (@zones) {
        printf "%s%s%s  %s%s%s%s\n",
            $C_NAME, $z->{name}, $C_OFF,
            $C_TYPE, $z->{status}, $C_OFF,
            $z->{paused} ? "  paused" : "";
    }
    exit 0;
}

# 获取 Zone ID
my $zones = api_request('GET', "/zones?name=$zone_name");
die "未找到域名 $zone_name（检查 Token 权限）\n" unless @$zones;
my $zone_id = $zones->[0]{id};

print "Zone: $zone_name\n";
print "$SEP\n";

# 拉取全部现有记录
my @all;
my $page = 1;
while (1) {
    my $res = api_request('GET', "/zones/$zone_id/dns_records?per_page=100&page=$page");
    push @all, @$res;
    last if @$res < 100;
    $page++;
}

# 新增
if ($action eq 'add') {
    for my $c (@contents) {
        my ($dup) = grep {
            lc($_->{name}) eq lc($add_name)
                && lc($_->{type}) eq lc($add_type)
                && lc($_->{content}) eq lc($c)
        } @all;
        if ($dup) {
            print "已存在: $C_NAME$add_name$C_OFF. $C_TTL Auto$C_OFF $C_TYPE$add_type$C_OFF $C_CONTENT$c$C_OFF，跳过。\n";
            next;
        }
        print "ADD    $C_NAME$add_name$C_OFF. $C_TTL Auto$C_OFF $C_TYPE$add_type$C_OFF $C_CONTENT$c$C_OFF\n";
        if (!$dry_run) {
            my %body = (
                type    => $add_type,
                name    => $add_name,
                content => $c,
                ttl     => 1,
                proxied => JSON::PP::false(),
            );
            $body{tags} = \@tags if defined $tags_str;
            $body{comment} = $comment_opt if $write_comment;
            api_request('POST', "/zones/$zone_id/dns_records", \%body);
        }
    }
    print "（dry-run 模式，未实际写入 Cloudflare）\n" if $dry_run;
    exit 0;
}

# 筛选
my $name_match;
if (defined $prefix) {
    $name_match = sub { $_[0] =~ /^\Q$prefix\E/i };
} elsif (defined $suffix) {
    $name_match = sub { $_[0] =~ /\Q$suffix\E$/i };
} elsif (defined $regex) {
    my $re = eval { qr/$regex/i } or die "无效的正则 --regex: $@";
    $name_match = sub { $_[0] =~ $re };
} else {
    $name_match = sub { 1 };
}
my @web = sort { lc($a->{name}) cmp lc($b->{name}) } grep {
    $name_match->($_->{name})
        && (!defined $type || lc($_->{type}) eq lc($type))
} @all;
print "匹配：" . scalar(@web) . "/" . scalar(@all) . "\n";
print "$SEP\n";

if (!@web) {
    print "没有找到任何匹配记录，退出。\n";
    exit 0;
}

# 列出
if ($action eq 'list') {
    for my $rec (@web) {
        printf "%s%s%s. %s%s%s %s%s%s %s%s%s%s%s\n",
            $C_NAME, $rec->{name}, $C_OFF,
            $C_TTL, ttl_str($rec->{ttl}), $C_OFF,
            $C_TYPE, $rec->{type}, $C_OFF,
            $C_CONTENT, $rec->{content}, $C_OFF,
            $rec->{proxied} ? " Proxy" : " DNS",
            $show_comment && defined $rec->{comment} && length $rec->{comment}
                ? "  # $rec->{comment}" : "";
    }
    exit 0;
}

# 修改 content
if ($action eq 'edit') {
    my @targets;
    if (!@contents) {
        @targets = map { $_->{content} } @web;
    } elsif (@contents == 1) {
        @targets = ($contents[0]) x @web;
    } elsif (@contents == @web) {
        @targets = @contents;
    } else {
        die "内容数量(" . scalar(@contents) . ")与匹配记录数(" . scalar(@web) . ")不一致\n";
    }

    my ($ok, $upd, $fail) = (0, 0, 0);
    for my $i (0 .. $#web) {
        my $rec     = $web[$i];
        my $content = $targets[$i];

        if (lc($rec->{content}) eq lc($content) && !defined $tags_str && !$write_comment) {
            print "OK     $C_NAME$rec->{name}$C_OFF\n";
            $ok++;
            next;
        }
        printf "UPDATE %s%s%s.  %s%s%s %s%s%s %s%s%s → %s%s%s%s%s\n",
            $C_NAME, $rec->{name}, $C_OFF,
            $C_TTL, ttl_str($rec->{ttl}), $C_OFF,
            $C_TYPE, $rec->{type}, $C_OFF,
            $C_CONTENT, $rec->{content}, $C_OFF,
            $C_CONTENT, $content, $C_OFF,
            $rec->{proxied} ? " Proxy" : " DNS",
            $show_comment && defined $rec->{comment} && length $rec->{comment}
                ? "  # $rec->{comment}" : "";

        if (!$dry_run) {
            my $err;
            eval {
                my %body = (
                    type    => $rec->{type},
                    name    => $rec->{name},
                    content => $content,
                    ttl     => 1,
                    proxied => $rec->{proxied},
                );
                $body{tags} = \@tags if defined $tags_str;
                $body{comment} = $comment_opt if $write_comment;
                api_request('PUT', "/zones/$zone_id/dns_records/$rec->{id}", \%body);
                1;
            } or $err = $@;
            if ($err) { warn "  失败: $err"; $fail++; next; }
        }
        $upd++;
    }
    print "$SEP\n";
    printf "OK=%d  UPDATE=%d  FAILED=%d\n", $ok, $upd, $fail;
    print "（dry-run 模式，未实际写入 Cloudflare）\n" if $dry_run;
    exit 0;
}

# 删除
my %want = map { lc($_) => 1 } @contents;
my @del = @contents
    ? grep { $want{lc($_->{content})} } @web
    : @web;

my ($ok, $fail) = (0, 0);
for my $rec (@del) {
    printf "DELETE %s%s%s.  %s%s%s %s%s%s %s%s%s%s%s\n",
        $C_NAME, $rec->{name}, $C_OFF,
        $C_TTL, ttl_str($rec->{ttl}), $C_OFF,
        $C_TYPE, $rec->{type}, $C_OFF,
        $C_CONTENT, $rec->{content}, $C_OFF,
        $rec->{proxied} ? " Proxy" : " DNS",
        $show_comment && defined $rec->{comment} && length $rec->{comment}
            ? "  # $rec->{comment}" : "";
    if (!$dry_run) {
        my $err;
        eval { api_request('DELETE', "/zones/$zone_id/dns_records/$rec->{id}"); 1; }
            or $err = $@;
        if ($err) { warn "  失败: $err"; $fail++; next; }
    }
    $ok++;
}
print "$SEP\n";
printf "DELETED=%d  FAILED=%d\n", $ok, $fail;
print "（dry-run 模式，未实际写入 Cloudflare）\n" if $dry_run;
