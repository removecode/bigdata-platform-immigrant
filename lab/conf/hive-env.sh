export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
export HADOOP_HOME=/opt/lab/hadoop
export HADOOP_CONF_DIR=/opt/lab/hadoop/etc/hadoop
export HIVE_CONF_DIR=/opt/lab/hive/conf
export HADOOP_HEAPSIZE=384

# Java 21 refuses reflective access unless these modules are opened.
HIVE_OPENS="\
--add-opens=java.base/java.lang=ALL-UNNAMED \
--add-opens=java.base/java.lang.invoke=ALL-UNNAMED \
--add-opens=java.base/java.lang.reflect=ALL-UNNAMED \
--add-opens=java.base/java.io=ALL-UNNAMED \
--add-opens=java.base/java.net=ALL-UNNAMED \
--add-opens=java.base/java.nio=ALL-UNNAMED \
--add-opens=java.base/java.util=ALL-UNNAMED \
--add-opens=java.base/java.util.concurrent=ALL-UNNAMED \
--add-opens=java.base/java.util.concurrent.atomic=ALL-UNNAMED \
--add-opens=java.base/sun.nio.ch=ALL-UNNAMED \
--add-opens=java.base/sun.nio.cs=ALL-UNNAMED \
--add-opens=java.base/sun.security.action=ALL-UNNAMED \
--add-opens=java.base/sun.util.calendar=ALL-UNNAMED \
--add-opens=java.security.jgss/sun.security.krb5=ALL-UNNAMED \
--add-opens=java.management/sun.management=ALL-UNNAMED"
export HIVE_AUX_JARS_PATH="${HIVE_AUX_JARS_PATH:-/opt/lab/udf/lab-udf.jar}"
export HADOOP_OPTS="${HADOOP_OPTS:-} ${HIVE_OPENS} -Xmx384m"
export HADOOP_CLIENT_OPTS="${HADOOP_CLIENT_OPTS:-} ${HIVE_OPENS} -Xmx512m"
