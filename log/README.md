## Oozie使用经验

----------

### 简介

Oozie是一个工作流引擎服务器,用于运行Hadoop Map/Reduce和Hive等任务工作流。
Oozie以action为基本任务单位，可以将多个action构成一个DAG图（有向无环图Direct Acyclic Graph）的模式进行运行。
Oozie工作流通过HPDL(一种通过XML自定义处理的语言)来构造Oozie的工作流。

* Oozie config：用于定义一些变量。
* Oozie Workflow： 该组件用于定义和执行一个特定顺序的mapreduce、hive和pig作业。
* Oozie Coordinator：该组件用于支持基于事件、系统资源存在性等条件的workflow的自动化执行。

开发时只需在jobs下ShenZhen或者FLKF进行修改即可，可以参考其他同级目录。

deploy.py文件是将任务提交至HDFS，测试时可以修改其START_DATE参数，让代码立刻执行。

测试时，在容器内进入相应目录执行时需要加要执行的任务，
如使用命令sh start-task.sh run af_blackip_operation_weekly
即可启动af_blackip_operation_weekly这个任务，如果不加参数会启动所有任务！

