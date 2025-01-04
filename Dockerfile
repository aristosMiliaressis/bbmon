FROM ubuntu:20.04

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y cron curl gcc git jq musl-dev wget

COPY --from=golang:1.21 /usr/local/go/ /usr/local/go/
ENV GOROOT "/usr/local/go"
ENV GOPATH "/root/go"
ENV PATH "$PATH:$GOPATH/bin:$GOROOT/bin"

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends fonts-liberation \
        libu2f-udev libgtk-3-dev libnotify-dev libgconf-2-4 libnss3 libxss1 libasound2 xdg-utils xvfb

ARG NODE_VERSION=v18.20.5
RUN curl -fsSL https://nodejs.org/dist/$NODE_VERSION/node-$NODE_VERSION-linux-x64.tar.gz -o node.tar.gz \
    && tar -xzvf node.tar.gz -C /usr/local/lib && rm node.tar.gz
ENV PATH "$PATH:/usr/local/lib/node-$NODE_VERSION-linux-x64/bin"

RUN wget https://github.com/cli/cli/releases/download/v2.64.0/gh_2.64.0_linux_amd64.tar.gz \
    && tar xzf gh_2.64.0_linux_amd64.tar.gz \
    && mv gh_2.64.0_linux_amd64/bin/gh /usr/local/bin \
    && rm -rf gh_2.64.0_linux_amd64* 

RUN wget https://github.com/mgdm/htmlq/releases/download/v0.4.0/htmlq-x86_64-linux.tar.gz \
    && tar xzf htmlq-x86_64-linux.tar.gz \
    && rm htmlq-x86_64-linux.tar.gz \
    && mv htmlq /usr/local/bin
     
RUN go install github.com/mikefarah/yq/v4@latest
RUN go install github.com/projectdiscovery/notify/cmd/notify@latest
RUN go install github.com/BishopFox/jsluice/cmd/jsluice@latest
RUN go install github.com/tomnomnom/unfurl@latest
RUN go install github.com/tomnomnom/anew@latest

RUN npm install -g stealthy-har-capturer@1.3.8
RUN npm install -g @mixer/parallel-prettier

RUN git config --global user.email "you@example.com" \
 && git config --global user.name "Your Name"

COPY ./entrypoint.sh /entrypoint.sh
COPY ./bin /usr/local/bin
RUN chmod +x /usr/local/bin/*

RUN mkdir /mnt/data

ENTRYPOINT ["/entrypoint.sh"]
