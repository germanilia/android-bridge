FROM gradle:8.10.2-jdk17-alpine@sha256:bc4cfcd317082aa35b3d5d86bbaa90f958fc3a3088ac8077db9dc443c1a347e7 AS build
WORKDIR /workspace
COPY settings.gradle.kts build.gradle.kts gradle.properties gradle.lockfile ./
COPY src ./src
RUN --mount=type=cache,target=/home/gradle/.gradle gradle --no-daemon clean jar

FROM eclipse-temurin:17.0.15_6-jre-alpine@sha256:2f5f20b9dd8f70c30ed1eba9fdf362d2abf4eac45376a29fb7c8a5e919d0da68 AS runtime
RUN addgroup -S -g 10001 relay \
    && adduser -S -D -H -u 10001 -G relay relay \
    && mkdir -p /app /config \
    && chown -R relay:relay /app /config
WORKDIR /app
COPY --from=build --chown=relay:relay /workspace/build/libs/android-bridge-relay-1.0.0.jar /app/relay.jar
USER 10001:10001
EXPOSE 8080
VOLUME ["/config"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=5 \
    CMD wget -q -O /dev/null http://127.0.0.1:8080/health || exit 1
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75", "-jar", "/app/relay.jar"]
