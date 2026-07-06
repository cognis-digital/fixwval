# fixwval — FIX Wire Validator
# Builds a standalone GnuCOBOL executable and runs it as the entrypoint.
FROM ubuntu:24.04

RUN apt-get update \
 && apt-get install -y --no-install-recommends gnucobol \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY fixwval.cob fwmode.cob ./
RUN cobc -x -free -o /usr/local/bin/fixwval fixwval.cob \
 && cobc -x -free -o /usr/local/bin/fwmode  fwmode.cob

# Mount your messages and pass the path, e.g.:
#   docker run --rm -v "$PWD:/data" fixwval /data/session.fix
WORKDIR /data
ENTRYPOINT ["fixwval"]
