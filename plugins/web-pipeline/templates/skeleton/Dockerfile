# The UI as static files behind unprivileged nginx (factory ADR 0035): it runs as uid 101 and listens on 8080.
# Build dist/ first (`npm ci && npm run build`); the image holds no Node and no sources.
# The base is pinned to a digest (factory ADR 0009); the version is in the tag for people.
FROM nginxinc/nginx-unprivileged:1.30.6-alpine@sha256:f5116ed4606f3eb015dd4a8e28cb9b351476dc0ad4bc6e9f93b19cec130cdf03

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY dist/ /usr/share/nginx/html/

EXPOSE 8080
