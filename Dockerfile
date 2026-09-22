FROM maven:3-eclipse-temurin-21
WORKDIR /app
COPY . .
RUN mvn clean install 
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "target/*.jar"]