# ref: https://hub.docker.com/_/python

FROM python:3.15.0b1-alpine3.23

WORKDIR /usr/src/app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

CMD [ "pytest" ]
