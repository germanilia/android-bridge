FROM gradle:8.10.2-jdk17-jammy@sha256:c2900027f3f0681c2cbfb09d527813851ad67aeafbb409997297efa2df20e748 AS build
WORKDIR /workspace
COPY settings.gradle.kts build.gradle.kts gradle.properties gradle.lockfile ./
COPY src ./src
RUN --mount=type=cache,target=/home/gradle/.gradle gradle --no-daemon clean jar

FROM eclipse-temurin:17.0.15_6-jre-jammy@sha256:c831c9b41c682d013944b2b4fa4b7f59685cd7f237da58f88302f2299fe7aecf AS runtime
RUN groupadd --gid 10001 relay \
    && useradd --uid 10001 --gid relay --no-create-home --shell /usr/sbin/nologin relay \
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
