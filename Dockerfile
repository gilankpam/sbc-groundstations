FROM ubuntu:22.04

# Install buildroot dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    sed \
    make \
    binutils \
    gcc \
    g++ \
    bash \
    patch \
    gzip \
    bzip2 \
    perl \
    tar \
    cpio \
    unzip \
    rsync \
    file \
    wget \
    git \
    build-essential \
    libncurses5-dev \
    libncursesw5-dev \
    bc \
    curl

# Install Node.js 24 (LTS)
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - && \
    apt-get install -y nodejs

# Set the working directory
WORKDIR /project

ENV FORCE_UNSAFE_CONFIGURE=1

# Run the build
CMD ["./build.sh"]
