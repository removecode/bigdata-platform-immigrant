#!/usr/bin/env bash
set -Eeuo pipefail

# 批量将指定消费组在指定 topic 上的 offset 重置到今天 18:00（Asia/Shanghai）。
#
# 用法：
#   BOOTSTRAP_SERVER='kafka-1:9092,kafka-2:9092' \
#   KAFKA_BIN='/opt/kafka/bin/kafka-consumer-groups.sh' \
#   ./reset_kafka_offsets_to_today_1800.sh              # 仅预览
#
# 真正执行：
#   BOOTSTRAP_SERVER='kafka-1:9092,kafka-2:9092' \
#   ./reset_kafka_offsets_to_today_1800.sh --execute
#
# 如 Kafka 启用了认证，请设置 COMMAND_CONFIG 指向 client.properties。

BOOTSTRAP_SERVER="${BOOTSTRAP_SERVER:-szbwx-paas-k8s-worker-1.novalocal:31410,szbwx-paas-k8s-worker-1.novalocal:31411,szbwx-paas-k8s-worker-1.novalocal:31412,szbwx-paas-k8s-worker-1.novalocal:31413,szbwx-paas-k8s-worker-1.novalocal:31414}"
KAFKA_BIN="${KAFKA_BIN:-kafka-consumer-groups.sh}"
COMMAND_CONFIG="${COMMAND_CONFIG:-}"
MODE="preview"

if [[ "${1:-}" == "--execute" ]]; then
  MODE="execute"
elif [[ "${1:-}" != "" ]]; then
  echo "用法: $0 [--execute]" >&2
  exit 2
fi

# Kafka CLI 的 --to-datetime 按运行时本地时区解释；显式设置为中国时区。
export TZ="Asia/Shanghai"
TARGET_DATETIME="${TARGET_DATETIME:-2026-09-22T10:00:00.000}"

TOPICS=(
  "incr.ShenZhen.mongo-filecloud.db_fc_hashinfo"
  "incr.ShenZhen.mongo-tim.db_domain_intelligence"
  "incr.ShenZhen.mongo-tim.db_intelligence"
  "incr.ShenZhen.mongo-tim.db_unknown_intelligence"
  "incr.ShenZhen.mongo-tim.db_url_intelligence"
  "incr.ShenZhenBWX.mongo-int.SCIA_INTELLIGENCE"
  "incr.ShenZhenBWX.mongo-ci.SCIA_URL_CATEGORY"
  "incr.ShenZhen.mongo-int.db_statistic"
)

CONSUMER_GROUPS=(
  "transfer.fft.incr.ShenZhenBWX.mongo-int.SCIA_INTELLIGENCE.CloudLibURL_EN"
  "transfer.fft.incr.ShenZhenBWX.mongo-int.SCIA_INTELLIGENCE.CloudMetaInfo"
  "transfer.fft.incr.ShenZhenBWX.mongo-int.SCIA_INTELLIGENCE.CloudTopURL_EN"
  "transfer.fft.incr.ShenZhenBWX.mongo-int.SCIA_INTELLIGENCE.SynTrMaliceLinkStatisticLink"
  "transfer.fft.incr.ShenZhenBWX.mongo-int.SCIA_INTELLIGENCE.tb_domain_hot_stat"
  "transfer.flkf.incr.ShenZhenBWX.mongo-int.SCIA_INTELLIGENCE.BlackFileHotStat"
  "transfer.flkf.incr.ShenZhenBWX.mongo-int.SCIA_INTELLIGENCE.CloudChangeStream"
  "transfer.mlxy.incr.ShenZhenBWX.mongo-ci.SCIA_URL_CATEGORY.SynTrDomain3Index"
  "transfer.mlxy.incr.ShenZhenBWX.mongo-int.SCIA_INTELLIGENCE.BlackFileHotStat"
  "transfer.fft.incr.ShenZhenBWX.mongo-int.SCIA_INTELLIGENCE.CloudChangeStream"
  "transfer.fft.incr.ShenZhenBWX.mongo-int.SCIA_INTELLIGENCE.CloudScannerInfo"
  "transfer.fft.incr.ShenZhenBWX.mongo-int.SCIA_INTELLIGENCE.SynTiIOC"
  "transfer.fft.incr.ShenZhenBWX.mongo-int.SCIA_INTELLIGENCE.SynTiTagsAssociationView"
  "transfer.fft.incr.ShenZhenBWX.mongo-int.SCIA_INTELLIGENCE.SynTrUTMBlackDNS"
  "transfer.fft.incr.ShenZhenBWX.mongo-int.SCIA_INTELLIGENCE.SynTrUTMBlackURL"
  "transfer.flkf.incr.ShenZhen.mongo-filecloud.db_fc_hashinfo.tb_fc_hashinfo"
  "transfer.flkf.incr.ShenZhenBWX.mongo-int.SCIA_INTELLIGENCE.tb_domain_hot_stat"
  "transfer.mlxy.incr.ShenZhenBWX.mongo-int.SCIA_INTELLIGENCE.CloudChangeStream"
  "transfer.sz.incr.ShenZhenBWX.mongo-ci.SCIA_URL_CATEGORY.SynTrUrlCategory"
  "transfer.fft.incr.ShenZhenBWX.mongo-int.SCIA_INTELLIGENCE.BlackFileHotStat"
  "transfer.fft.incr.ShenZhenBWX.mongo-int.SCIA_INTELLIGENCE.CloudLibFile"
  "transfer.fft.incr.ShenZhenBWX.mongo-int.SCIA_INTELLIGENCE.CloudTopDomain"
  "transfer.fft.incr.ShenZhenBWX.mongo-int.SCIA_INTELLIGENCE.CloudTopVuln"
  "transfer.fft.incr.ShenZhenBWX.mongo-int.SCIA_INTELLIGENCE.SynTiTags"
  "transfer.fft.incr.ShenZhenBWX.mongo-int.SCIA_INTELLIGENCE.SynTrAttackBlackIP"
  "transfer.flkf.incr.ShenZhenBWX.mongo-ci.SCIA_URL_CATEGORY.SynTrDomain3Index"
  "transfer.flkf.incr.ShenZhenBWX.mongo-ci.SCIA_URL_CATEGORY.SynTrUrlCategory"
  "transfer.mlxy.incr.ShenZhenBWX.mongo-int.SCIA_INTELLIGENCE.CloudTask"
  "transfer.mlxy.incr.ShenZhenBWX.mongo-int.SCIA_INTELLIGENCE.tb_domain_hot_stat"
  "transfer.fft.incr.ShenZhenBWX.mongo-ci.SCIA_URL_CATEGORY.SynTrDomain3Index"
  "transfer.fft.incr.ShenZhenBWX.mongo-int.SCIA_INTELLIGENCE.CloudLibC2IP"
  "transfer.fft.incr.ShenZhenBWX.mongo-int.SCIA_INTELLIGENCE.CloudLibDomain_EN"
  "transfer.fft.incr.ShenZhenBWX.mongo-int.SCIA_INTELLIGENCE.CloudLibIP"
  "transfer.fft.incr.ShenZhenBWX.mongo-int.SCIA_INTELLIGENCE.CloudTask"
  "transfer.fft.incr.ShenZhenBWX.mongo-int.SCIA_INTELLIGENCE.CloudTopC2IP"
  "transfer.fft.incr.ShenZhenBWX.mongo-int.SCIA_INTELLIGENCE.CloudTopIP"
  "transfer.fft.incr.ShenZhenBWX.mongo-int.SCIA_INTELLIGENCE.SynTrHotBlackFileStatistic"
  "transfer.fft.incr.ShenZhenBWX.mongo-int.SCIA_INTELLIGENCE.SynTrMaliceLinkBlackLink"
  "transfer.fft.incr.ShenZhenBWX.mongo-int.SCIA_INTELLIGENCE.SynTrUTMStatisticDNS"
  "transfer.fft.incr.ShenZhenBWX.mongo-int.SCIA_INTELLIGENCE.SynTrUTMWhiteDNS"
  "transfer.fft.incr.ShenZhenBWX.mongo-int.SCIA_INTELLIGENCE.tb_url_hot_stat"
  "transfer.flkf.incr.ShenZhenBWX.mongo-int.SCIA_INTELLIGENCE.tb_url_hot_stat"
  "transfer.mlxy.incr.ShenZhen.mongo-filecloud.db_fc_hashinfo.tb_fc_hashinfo"
  "transfer.sz.incr.ShenZhenBWX.mongo-ci.SCIA_URL_CATEGORY.SynTrDomain3Index"
  "transfer.fft.incr.ShenZhenBWX.mongo-ci.SCIA_URL_CATEGORY.SynTrUrlCategory"
  "transfer.fft.incr.ShenZhenBWX.mongo-int.SCIA_INTELLIGENCE.CloudLibDomain"
  "transfer.fft.incr.ShenZhenBWX.mongo-int.SCIA_INTELLIGENCE.CloudLibNewIOC"
  "transfer.fft.incr.ShenZhenBWX.mongo-int.SCIA_INTELLIGENCE.CloudLibURL"
  "transfer.fft.incr.ShenZhenBWX.mongo-int.SCIA_INTELLIGENCE.CloudLibVuln"
  "transfer.fft.incr.ShenZhenBWX.mongo-int.SCIA_INTELLIGENCE.CloudTopDomain_EN"
  "transfer.fft.incr.ShenZhenBWX.mongo-int.SCIA_INTELLIGENCE.CloudTopFile"
  "transfer.fft.incr.ShenZhenBWX.mongo-int.SCIA_INTELLIGENCE.CloudTopNewIOC"
  "transfer.fft.incr.ShenZhenBWX.mongo-int.SCIA_INTELLIGENCE.CloudTopURL"
  "transfer.flkf.incr.ShenZhenBWX.mongo-int.SCIA_INTELLIGENCE.CloudTask"
  "transfer.mlxy.incr.ShenZhenBWX.mongo-ci.SCIA_URL_CATEGORY.SynTrUrlCategory"
  "transfer.mlxy.incr.ShenZhenBWX.mongo-int.SCIA_INTELLIGENCE.tb_url_hot_stat"
)

echo "目标时间: ${TARGET_DATETIME} (Asia/Shanghai)"
echo "消费组: ${#CONSUMER_GROUPS[@]}，topic: ${#TOPICS[@]}，模式: ${MODE}"

failures=()
for group in "${CONSUMER_GROUPS[@]}"; do
  # 每个消费组只处理其名称中对应的源 topic，避免创建无关的 group-topic offset。
  topic=""
  for candidate in "${TOPICS[@]}"; do
    if [[ "$group" == *."$candidate".* ]]; then
      if [[ -n "$topic" ]]; then
        echo "消费组匹配到多个 topic，拒绝处理: $group" >&2
        topic=""
        break
      fi
      topic="$candidate"
    fi
  done
  if [[ -z "$topic" ]]; then
    echo "未找到唯一匹配的 topic，跳过: $group" >&2
    failures+=("$group")
    continue
  fi

  args=(
    "--bootstrap-server" "$BOOTSTRAP_SERVER"
    "--group" "$group"
    "--topic" "$topic"
    "--to-datetime" "$TARGET_DATETIME"
    "--reset-offsets"
  )
  [[ -n "$COMMAND_CONFIG" ]] && args+=("--command-config" "$COMMAND_CONFIG")
  [[ "$MODE" == "execute" ]] && args+=("--execute") || args+=("--dry-run")
  echo "[$MODE] group=$group topic=$topic"
  printf '执行命令:'
  printf ' %q' "$KAFKA_BIN" "${args[@]}"
  printf '\n'
  if ! "$KAFKA_BIN" "${args[@]}"; then
    failures+=("$group")
    echo "处理失败，继续下一个消费组: $group" >&2
  fi
done

if ((${#failures[@]} > 0)); then
  echo "处理完成，但有 ${#failures[@]} 个消费组失败:" >&2
  printf '  %s\n' "${failures[@]}" >&2
  exit 1
fi

echo "处理完成，全部消费组成功。"
