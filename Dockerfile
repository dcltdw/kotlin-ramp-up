# The jar is built by Gradle before this runs — deliberately not compiled here.
# The EC2 instance is a t4g.small (1 GB, Graviton); compiling on the box, or
# even running a Gradle build stage in this image, is exactly what that
# instance is too small to do well.
#
# Because a JVM jar is architecture-neutral, targeting linux/arm64 from an
# x86 laptop is a plain layer copy over an arm64 base — no emulation, no
# cross-compilation, no slow qemu build.
FROM eclipse-temurin:21-jre

RUN groupadd --system --gid 1001 app \
    && useradd --system --uid 1001 --gid app --no-create-home app

WORKDIR /app
COPY build/libs/*.jar app.jar
USER app

EXPOSE 8080

# MaxRAMPercentage rather than a fixed -Xmx: the JVM reads the container limit,
# so the same image behaves sensibly on a 1 GB t4g.small and on a laptop.
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75.0", "-jar", "/app/app.jar"]
