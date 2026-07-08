FROM eclipse-temurin:21-jre-alpine
COPY target/media*.jar app.jar
COPY images /images
ENTRYPOINT ["java","-jar","/app.jar"]
