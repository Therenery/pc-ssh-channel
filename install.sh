#!/usr/bin/env bash
# install.sh —— 把 bin/ 下的脚本装到 ~/.local/bin，并生成一份配置模板
set -eu

SRC=$(cd "$(dirname "$0")" && pwd)
DEST="${PREFIX:-$HOME/.local/bin}"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/pc"
CONF="$CONF_DIR/pc.conf"

mkdir -p "$DEST" "$CONF_DIR"
install -m 755 "$SRC"/bin/* "$DEST"/
echo "已安装到 $DEST"

if [ ! -f "$CONF" ]; then
  install -m 644 "$SRC/config/pc.conf.example" "$CONF"
  echo "已生成配置: $CONF"
  echo "请先编辑它，填入你的电脑地址与用户名。"
else
  echo "配置已存在，未覆盖: $CONF"
fi

case ":$PATH:" in
  *":$DEST:"*) ;;
  *) echo "提醒：$DEST 不在 PATH 里，请把它加进 shell 启动文件。" ;;
esac
