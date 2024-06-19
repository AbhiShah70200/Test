To convert the given code to a pure Spring Boot application without using Spring Data JPA, we will create a structured project with the following components:

1. **`src/main/java/com/example/dbqueryexecutor/DatabaseQueryExecutorApplication.java`**: The main class to run the Spring Boot application.
2. **`src/main/java/com/example/dbqueryexecutor/controller/QueryController.java`**: REST controller to handle HTTP requests.
3. **`src/main/java/com/example/dbqueryexecutor/service/DatabaseQueryService.java`**: Service to encapsulate the database query and Excel writing logic.
4. **`src/main/java/com/example/dbqueryexecutor/model/QueryRequest.java`**: Model to handle the request payload.
5. **`src/main/resources/application.properties`**: Configuration file for database connection and other properties.

### Project Structure
```text
src
└── main
    ├── java
    │   └── com
    │       └── example
    │           └── dbqueryexecutor
    │               ├── DatabaseQueryExecutorApplication.java
    │               ├── controller
    │               │   └── QueryController.java
    │               ├── model
    │               │   └── QueryRequest.java
    │               └── service
    │                   └── DatabaseQueryService.java
    └── resources
        └── application.properties
```

### 1. `DatabaseQueryExecutorApplication.java`
```java
package com.example.dbqueryexecutor;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class DatabaseQueryExecutorApplication {

    public static void main(String[] args) {
        SpringApplication.run(DatabaseQueryExecutorApplication.class, args);
    }
}
```

### 2. `QueryController.java`
```java
package com.example.dbqueryexecutor.controller;

import com.example.dbqueryexecutor.model.QueryRequest;
import com.example.dbqueryexecutor.service.DatabaseQueryService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;

@RestController
@RequestMapping("/api/query")
public class QueryController {

    @Autowired
    private DatabaseQueryService queryService;

    @PostMapping("/execute")
    public ResponseEntity<String> executeQuery(@RequestParam("queryFile") MultipartFile queryFile,
                                               @RequestParam("outputFile") String outputFile,
                                               @RequestBody QueryRequest queryRequest) {
        try {
            String query = new String(queryFile.getBytes());
            queryService.executeQueryAndWriteToExcel(query, outputFile, queryRequest.getExtractionColumns());
            return ResponseEntity.ok("Query executed and results written to " + outputFile);
        } catch (IOException e) {
            return ResponseEntity.badRequest().body("Failed to read query file: " + e.getMessage());
        }
    }
}
```

### 3. `DatabaseQueryService.java`
```java
package com.example.dbqueryexecutor.service;

import org.apache.poi.ss.usermodel.Row;
import org.apache.poi.ss.usermodel.Sheet;
import org.apache.poi.ss.usermodel.Workbook;
import org.apache.poi.xssf.usermodel.XSSFWorkbook;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.io.FileOutputStream;
import java.io.IOException;
import java.sql.*;
import java.util.*;

@Service
public class DatabaseQueryService {

    @Value("${spring.datasource.url}")
    private String jdbcUrl;

    @Value("${spring.datasource.username}")
    private String jdbcUser;

    @Value("${spring.datasource.password}")
    private String jdbcPassword;

    public void executeQueryAndWriteToExcel(String query, String outputFilePath, List<String> extractionColumns) {
        try (Connection connection = DriverManager.getConnection(jdbcUrl, jdbcUser, jdbcPassword);
             Statement statement = connection.createStatement(ResultSet.TYPE_SCROLL_INSENSITIVE, ResultSet.CONCUR_READ_ONLY);
             ResultSet resultSet = statement.executeQuery(query);
             Workbook workbook = new XSSFWorkbook()) {

            Sheet sheet = workbook.createSheet("Query Results");

            ResultSetMetaData metaData = resultSet.getMetaData();
            int columnCount = metaData.getColumnCount();

            List<String> allColumns = new ArrayList<>();
            for (int i = 1; i <= columnCount; i++) {
                allColumns.add(metaData.getColumnName(i));
            }

            Map<String, Set<String>> columnKeysMap = new HashMap<>();
            for (String column : extractionColumns) {
                columnKeysMap.put(column, new HashSet<>());
            }

            while (resultSet.next()) {
                for (String column : extractionColumns) {
                    int columnIndex = resultSet.findColumn(column);
                    extractKeys(resultSet.getString(columnIndex), columnKeysMap.get(column));
                }
            }

            resultSet.beforeFirst();

            Row headerRow = sheet.createRow(0);
            int headerIndex = 0;
            Map<String, Integer> headerIndexes = new HashMap<>();

            for (String column : allColumns) {
                headerRow.createCell(headerIndex++).setCellValue(column);
            }

            for (String column : extractionColumns) {
                for (String key : columnKeysMap.get(column)) {
                    headerIndexes.put(column + ":" + key, headerIndex);
                    headerRow.createCell(headerIndex++).setCellValue(key);
                }
            }

            int rowIndex = 1;
            while (resultSet.next()) {
                Row row = sheet.createRow(rowIndex++);
                int cellIndex = 0;

                for (String column : allColumns) {
                    row.createCell(cellIndex++).setCellValue(resultSet.getString(column));
                }

                for (String column : extractionColumns) {
                    int columnIndex = resultSet.findColumn(column);
                    Map<String, String> keyValuePairs = parseKeyValuePairs(resultSet.getString(columnIndex));
                    for (Map.Entry<String, String> entry : keyValuePairs.entrySet()) {
                        int index = headerIndexes.get(column + ":" + entry.getKey());
                        row.createCell(index).setCellValue(entry.getValue());
                    }
                }
            }

            try (FileOutputStream fileOut = new FileOutputStream(outputFilePath)) {
                workbook.write(fileOut);
            }

        } catch (SQLException | IOException e) {
            e.printStackTrace();
        }
    }

    private void extractKeys(String text, Set<String> keys) {
        if (text != null && !text.isEmpty()) {
            String[] pairs = text.split("-");
            for (int i = 0; i < pairs.length - 1; i += 2) {
                keys.add(pairs[i].trim());
            }
        }
    }

    private Map<String, String> parseKeyValuePairs(String text) {
        Map<String, String> map = new HashMap<>();
        if (text != null && !text.isEmpty()) {
            String[] pairs = text.split("-");
            for (int i = 0; i < pairs.length - 1; i += 2) {
                map.put(pairs[i].trim(), pairs[i + 1].trim());
            }
        }
        return map;
    }
}
```

### 4. `QueryRequest.java`
```java
package com.example.dbqueryexecutor.model;

import java.util.List;

public class QueryRequest {
    private List<String> extractionColumns;

    public List<String> getExtractionColumns() {
        return extractionColumns;
    }

    public void setExtractionColumns(List<String> extractionColumns) {
        this.extractionColumns = extractionColumns;
    }
}
```

### 5. `application.properties`
```properties
spring.datasource.url=jdbc:sybase:Tds:hostname:port/dbname
spring.datasource.username=yourUsername
spring.datasource.password=yourPassword
```

### Setting Up the Project

1. **Create a Spring Boot Project**: Use Spring Initializr (https://start.spring.io/) to generate a new Spring Boot project. Include the dependencies for Spring Web and Apache POI.

2. **Add Dependencies**: Ensure the following dependencies are added to your `pom.xml`:
```xml
<dependencies>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-web</artifactId>
    </dependency>
    <dependency>
        <groupId>org.apache.poi</groupId>
        <artifactId>poi-ooxml</artifactId>
        <version>5.2.3</version>
    </dependency>
    <!-- Add your JDBC driver dependency for Sybase here -->
    <dependency>
        <groupId>com.sybase</groupId>
        <artifactId>jconn4</artifactId>
        <version>7.0</version>
    </dependency>
</dependencies>
```

3. **Configure Database Connection**: Update the `application.properties` file with your database connection details.

### Running the Application

1. **Start the Spring Boot Application**: Run `DatabaseQueryExecutorApplication.java` to start the Spring Boot application.

2. **Send a POST Request**: Use a tool like Postman to send a POST request to `http://localhost:8080/api/query/execute` with a multipart file for the SQL query and a JSON body for the extraction columns.

   Example of JSON body:
   ```json
   {
       "extractionColumns": ["column1", "column2"]
   }
   ```

This setup creates a Spring Boot application that reads database credentials from the `application.properties` file, handles HTTP requests to execute SQL queries, extracts key-value pairs, and writes the results to an Excel file.

uage
JavaKotlinGroovy
Spring Boot
3.3.1 (SNAPSHOT)3.3.03.2.7 (SNAPSHOT)3.2.6
Project Metadata
Group
com.example
Artifact
demo
Name
demo
Description
Demo project for Spring Boot
Package name
com.example.demo
Packaging
JarWar
Java
222117
DependenciesADD ...
No dependency selected
GENERATEEXPLORESHARE...

pom.xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>3.3.0</version>
    <relativePath/> <!-- lookup parent from repository -->
  </parent>
  <groupId>com.example</groupId>
  <artifactId>demo</artifactId>
  <version>0.0.1-SNAPSHOT</version>
  <name>demo</name>
  <description>Demo project for Spring Boot</description>
  <url/>
  <licenses>
    <license/>
  </licenses>
  <developers>
    <developer/>
  </developers>
  <scm>
    <connection/>
    <developerConnection/>
    <tag/>
    <url/>
  </scm>
  <properties>
    <java.version>17</java.version>
  </properties>
  <dependencies>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter</artifactId>
    </dependency>

    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-test</artifactId>
      <scope>test</scope>
    </dependency>
  </dependencies>

  <build>
    <plugins>
      <plugin>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-maven-plugin</artifactId>
      </plugin>
    </plugins>
  </build>

</project>

DOWNLOADCLOSE

pom.xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>3.3.0</version>
    <relativePath/> <!-- lookup parent from repository -->
  </parent>
  <groupId>com.example</groupId>
  <artifactId>demo</artifactId>
  <version>0.0.1-SNAPSHOT</version>
  <name>demo</name>
  <description>Demo project for Spring Boot</description>
  <url/>
  <licenses>
    <license/>
  </licenses>
  <developers>
    <developer/>
  </developers>
  <scm>
    <connection/>
    <developerConnection/>
    <tag/>
    <url/>
  </scm>
  <properties>
    <java.version>17</java.version>
  </properties>
  <dependencies>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter</artifactId>
    </dependency>

    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-test</artifactId>
      <scope>test</scope>
    </dependency>
  </dependencies>

  <build>
    <plugins>
      <plugin>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-maven-plugin</artifactId>
      </plugin>
    </plugins>
  </build>

</project>


radle - GroovyGradle - KotlinMaven
Language
JavaKotlinGroovy
Spring Boot
3.3.1 (SNAPSHOT)3.3.03.2.7 (SNAPSHOT)3.2.6
Project Metadata
Group
com.example
Artifact
demo
Name
demo
Description
Demo project for Spring Boot
Package name
com.example.demo
Packaging
JarWar
Java
222117
DependenciesADD ...
No dependency selected
GENERATEEXPLORESHARE...

pom.xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>3.3.0</version>
    <relativePath/> <!-- lookup parent from repository -->
  </parent>
  <groupId>com.example</groupId>
  <artifactId>demo</artifactId>
  <version>0.0.1-SNAPSHOT</version>
  <name>demo</name>
  <description>Demo project for Spring Boot</description>
  <url/>
  <licenses>
    <license/>
  </licenses>
  <developers>
    <developer/>
  </developers>
  <scm>
    <connection/>
    <developerConnection/>
    <tag/>
    <url/>
  </scm>
  <properties>
    <java.version>17</java.version>
  </properties>
  <dependencies>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter</artifactId>
    </dependency>

    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-test</artifactId>
      <scope>test</scope>
    </dependency>
  </dependencies>

  <build>
    <plugins>
      <plugin>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-maven-plugin</artifactId>
      </plugin>
    </plugins>
  </build>

</project>

DOWNLOADCLOSE

pom.xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>3.3.0</version>
    <relativePath/> <!-- lookup parent from repository -->
  </parent>
  <groupId>com.example</groupId>
  <artifactId>demo</artifactId>
  <version>0.0.1-SNAPSHOT</version>
  <name>demo</name>
  <description>Demo project for Spring Boot</description>
  <url/>
  <licenses>
    <license/>
  </licenses>
  <developers>
    <developer/>
  </developers>
  <scm>
    <connection/>
    <developerConnection/>
    <tag/>
    <url/>
  </scm>
  <properties>
    <java.version>17</java.version>
  </properties>
  <dependencies>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter</artifactId>
    </dependency>

    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-test</artifactId>
      <scope>test</scope>
    </dependency>
  </dependencies>

  <build>
    <plugins>
      <plugin>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-maven-plugin</artifactId>
      </plugin>
    </plugins>
  </build>

</project>

DOWNLOADCLOSE
