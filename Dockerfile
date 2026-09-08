# The jar is built by Gradle before this runs — deliberately not compiled here.
# The EC2 instance is a t4g.small (2 GiB, Graviton); compiling on the box, or
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
# so the same image behaves sensibly on a 2 GiB t4g.small and on a laptop.
#
# Note what this delegates: the heap is sized from `docker run --memory`, not
# from the instance. Set that limit too low and the JVM quietly uses a fraction
# of the machine — see container_memory in infra/variables.tf.
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75.0", "-jar", "/app/app.jar"]
