FROM cube-sandbox-image.tencentcloudcr.com/opensource/tencentos4-minimal:4.4-v20250331
  

WORKDIR /work

RUN yum install -y \
    util-linux \
    busybox \
    gawk \
    gcc \
    util-linux \
    which \
    vim \
    sudo \
    lsof

RUN mkdir -p /etc \
    && if [ -L /etc/resolv.conf ]; then rm -f /etc/resolv.conf; fi \
    && touch /etc/resolv.conf \
    && touch /etc/hostname \
    && touch /etc/hosts

CMD ["bash"]
