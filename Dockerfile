FROM kbase/sdkbase:latest
RUN apt-get -y install mc
RUN apt-key adv --keyserver keyserver.ubuntu.com --recv 7F0CEB10 && \
  echo 'deb http://downloads-distro.mongodb.org/repo/ubuntu-upstart dist 10gen' | sudo tee /etc/apt/sources.list.d/mongodb.list && \
  apt-get update && \
  apt-get install mongodb-org=2.6.2 mongodb-org-server=2.6.2 mongodb-org-shell=2.6.2 mongodb-org-mongos=2.6.2 mongodb-org-tools=2.6.2
WORKDIR /kb/deployment/services
ENV PATH /kb/runtime/bin:$PATH
ENV KB_TOP /kb/dev_container

################### mongod ###################
RUN mkdir -p ./mongo/data
WORKDIR /kb/deployment/services/mongo
RUN echo '\
dbpath=/kb/deployment/services/mongo/data\n\
logpath=/scratch/mongo/mongod.log\n\
logappend=true\n\
port=27017\n\
bind_ip=127.0.0.1\n\
' > mongod.cfg
################### AWE server ###############
WORKDIR /kb/deployment/services/awe_service
RUN echo '\
[Admin]\nemail=shock-admin@kbase.us\nusers=\n\
[Anonymous]\nread=true\nwrite=true\ndelete=true\ncg_read=false\ncg_write=false\ncg_delete=false\n\
[Args]\ndebuglevel=0\n\
[Auth]\n\
globus_token_url=https://nexus.api.globusonline.org/goauth/token?grant_type=client_credentials\n\
globus_profile_url=https://nexus.api.globusonline.org/users\nclient_auth_required=false\n\
[Directories]\nsite=/mnt/awe/site\ndata=/mnt/awe/data\nlogs=/scratch/awe/logs\nawf=/mnt/awe/awfs\n\
[Mongodb]hosts=localhost:27017\ndatabase=AWEDB\n\
[Mongodb-Node-Indices]\nid=unique:true\n\
[Ports]\nsite-port=7108\napi-port=7080\n\
[External]\napi-url=http://deadendpoint:8080/services/awe-api/\n\
' > ./conf/my_awe.cfg
################### AWE client ###############
RUN echo '\
[Directories]\ndata=/mnt/awec/data\nlogs=/scratch/awec/logs\n\
[Args]\ndebuglevel=0\n\
[Client]\nworkpath=/scratch/awec/work\n\
supported_apps=trns_upload_taskrunner,trns_download_taskrunner,trns_convert_taskrunner\n\
serverurl=http://localhost:7080/\ngroup=prod\nname=kbase-client\nauto_clean_dir=false\n\
worker_overlap=false\nprint_app_msg=true\nclientgroup_token=\npre_work_script=\npre_work_script_args=\n\
' > ./conf/my_awec.cfg
################### Transform ################
WORKDIR /kb/dev_container/modules
RUN rm -rf ./transform
RUN git clone -b develop https://github.com/aekazakov/transform
WORKDIR /kb/dev_container/modules/transform
RUN sed -i 's/log_syslog = true/log_syslog = false/g' ./deploy.cfg
RUN sed -i 's/log_file = transform_service.log/log_file = \/scratch\/transform\/service.log/g' ./deploy.cfg
RUN sed -i 's/kbase.us/ci.kbase.us/g' ./deploy.cfg
RUN make && make deploy
################### Script running all 4 ##############
WORKDIR /kb/deployment/services/Transform
RUN echo '\
rm -rf /scratch/* \n\
mkdir -p /scratch/mongo \n\
cd /scratch/mongo \n\
mongod --config /kb/deployment/services/mongo/mongod.cfg >out.txt 2>err.txt & pid=$! \n\
echo $pid > pid.txt \n\
mkdir -p /scratch/awe/logs \n\
cd /scratch/awe \n\
awe-server -conf /kb/deployment/services/awe_service/conf/my_awe.cfg >out.txt 2>err.txt & pid=$! \n\
echo $pid > pid.txt \n\
mkdir -p /mnt/awec/data \n\
mkdir -p /scratch/awec/logs \n\
mkdir -p /scratch/awec/work \n\
cd /scratch/awec \n\
awe-client -conf /kb/deployment/services/awe_service/conf/my_awec.cfg >out.txt 2>err.txt & pid=$! \n\
echo $pid > pid.txt \n\
mkdir -p /scratch/transform \n\
cd /kb/deployment/services/Transform \n\
export KB_SERVICE_NAME=Transform \n\
export KB_TOP=/kb/deployment \n\
export KB_RUNTIME=/kb/runtime \n\
export KB_SERVICE_DIR=$KB_TOP/services/$KB_SERVICE_NAME \n\
export KB_DEPLOYMENT_CONFIG=$KB_SERVICE_DIR/service.cfg \n\
export PYTHONPATH=$KB_TOP/lib:$PYTHONPATH \n\
export PERL5LIB=$KB_TOP/lib:$KB_TOP/lib/perl5 \n\
pid_file=pid.txt \n\
wsgi_file=$KB_TOP/lib/biokbase/$KB_SERVICE_NAME/Server.py \n\
uwsgi --master --processes 5 --cheaper 4 --http :5000 --http-timeout 600 --pidfile $pid_file --daemonize /scratch/transform/uwsgi.log --wsgi-file $wsgi_file \n\
if [ -z $1 ]; then \n\
  while true; do sleep 3600; done \n\
else \n\
  $1 \n\
fi \n\
' > run.sh
##############################################
ENTRYPOINT [ "bash", "run.sh" ]
CMD [ "" ]
