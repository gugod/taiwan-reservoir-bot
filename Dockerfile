FROM docker.io/library/perl:5.36
WORKDIR /app
COPY . /app
RUN cpanm --notest --quiet --installdeps . \
    && rm -rf /root/.cpanm /root/.cpan
