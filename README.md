konoTo convert the given code to a pure Spring Boot application without using Spring Data JPA, we will create a structured project with the following components:

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



To modify the Spring Boot application to get input data through JSON and to accept a regex separator for splitting the key-value pairs, follow these steps:

1. **Update `QueryRequest.java`** to include the regex separator.
2. **Update `QueryController.java`** to accept the JSON request body directly.
3. **Update `DatabaseQueryService.java`** to use the regex separator from the request.

### Updated `QueryRequest.java`
Include a field for the regex separator in the request model.

```java
package com.example.dbqueryexecutor.model;

import java.util.List;

public class QueryRequest {
    private String query;
    private String outputFilePath;
    private List<String> extractionColumns;
    private String separatorRegex;

    // Getters and Setters

    public String getQuery() {
        return query;
    }

    public void setQuery(String query) {
        this.query = query;
    }

    public String getOutputFilePath() {
        return outputFilePath;
    }

    public void setOutputFilePath(String outputFilePath) {
        this.outputFilePath = outputFilePath;
    }

    public List<String> getExtractionColumns() {
        return extractionColumns;
    }

    public void setExtractionColumns(List<String> extractionColumns) {
        this.extractionColumns = extractionColumns;
    }

    public String getSeparatorRegex() {
        return separatorRegex;
    }

    public void setSeparatorRegex(String separatorRegex) {
        this.separatorRegex = separatorRegex;
    }
}
```

### Updated `QueryController.java`
Modify the controller to accept the JSON request body directly.

```java
package com.example.dbqueryexecutor.controller;

import com.example.dbqueryexecutor.model.QueryRequest;
import com.example.dbqueryexecutor.service.DatabaseQueryService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/query")
public class QueryController {

    @Autowired
    private DatabaseQueryService queryService;

    @PostMapping("/execute")
    public ResponseEntity<String> executeQuery(@RequestBody QueryRequest queryRequest) {
        try {
            queryService.executeQueryAndWriteToExcel(
                    queryRequest.getQuery(),
                    queryRequest.getOutputFilePath(),
                    queryRequest.getExtractionColumns(),
                    queryRequest.getSeparatorRegex()
            );
            return ResponseEntity.ok("Query executed and results written to " + queryRequest.getOutputFilePath());
        } catch (Exception e) {
            return ResponseEntity.badRequest().body("Failed to execute query: " + e.getMessage());
        }
    }
}
```

### Updated `DatabaseQueryService.java`
Update the service to use the regex separator from the request.

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

    public void executeQueryAndWriteToExcel(String query, String outputFilePath, List<String> extractionColumns, String separatorRegex) {
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
                    extractKeys(resultSet.getString(columnIndex), columnKeysMap.get(column), separatorRegex);
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
                    Map<String, String> keyValuePairs = parseKeyValuePairs(resultSet.getString(columnIndex), separatorRegex);
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

    private void extractKeys(String text, Set<String> keys, String separatorRegex) {
        if (text != null && !text.isEmpty()) {
            String[] pairs = text.split(separatorRegex);
            for (int i = 0; i < pairs.length - 1; i += 2) {
                keys.add(pairs[i].trim());
            }
        }
    }

    private Map<String, String> parseKeyValuePairs(String text, String separatorRegex) {
        Map<String, String> map = new HashMap<>();
        if (text != null && !text.isEmpty()) {
            String[] pairs = text.split(separatorRegex);
            for (int i = 0; i < pairs.length - 1; i += 2) {
                map.put(pairs[i].trim(), pairs[i + 1].trim());
            }
        }
        return map;
    }
}
```

### Sending the Request Through Postman

1. **Set Request Type and URL**:
   - Set the request type to `POST`.
   - Enter the URL: `http://localhost:8080/api/query/execute`.

2. **Set Up the Body**:
   - Go to the `Body` tab.
   - Select `raw`.
   - Select `JSON` from the dropdown menu.
   - Enter the JSON body.

#### Example JSON Body:
```json
{
    "query": "SELECT * FROM your_table",
    "outputFilePath": "output.xlsx",
    "extractionColumns": ["column1", "column2"],
    "separatorRegex": "-"
}
```

3. **Send the Request**:
   - Click `Send`.
   - Check the response section to see the server's response.

This setup modifies the Spring Boot application to accept input data through JSON and to allow specifying a regex separator for splitting key-value pairs.


To ensure the extracted fields are in order in the output, you need to maintain the order of the keys while processing the data. Here’s how you can modify your `DatabaseQueryService.java` to achieve this:

1. Use a `LinkedHashMap` instead of a `HashMap` to maintain the insertion order of keys.
2. Modify the code to process and maintain the order of columns and extracted keys.

Here is the modified `DatabaseQueryService.java`:

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

    public void executeQueryAndWriteToExcel(String query, String outputFilePath, List<String> extractionColumns, String separatorRegex) {
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

            // Use LinkedHashMap to maintain the order of keys
            Map<String, LinkedHashSet<String>> columnKeysMap = new LinkedHashMap<>();
            for (String column : extractionColumns) {
                columnKeysMap.put(column, new LinkedHashSet<>());
            }

            while (resultSet.next()) {
                for (String column : extractionColumns) {
                    int columnIndex = resultSet.findColumn(column);
                    extractKeys(resultSet.getString(columnIndex), columnKeysMap.get(column), separatorRegex);
                }
            }

            resultSet.beforeFirst();

            Row headerRow = sheet.createRow(0);
            int headerIndex = 0;
            Map<String, Integer> headerIndexes = new LinkedHashMap<>();

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
                    Map<String, String> keyValuePairs = parseKeyValuePairs(resultSet.getString(columnIndex), separatorRegex);
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

    private void extractKeys(String text, Set<String> keys, String separatorRegex) {
        if (text != null && !text.isEmpty()) {
            String[] pairs = text.split(separatorRegex);
            for (int i = 0; i < pairs.length - 1; i += 2) {
                keys.add(pairs[i].trim());
            }
        }
    }

    private Map<String, String> parseKeyValuePairs(String text, String separatorRegex) {
        Map<String, String> map = new LinkedHashMap<>();
        if (text != null && !text.isEmpty()) {
            String[] pairs = text.split(separatorRegex);
            for (int i = 0; i < pairs.length - 1; i += 2) {
                map.put(pairs[i].trim(), pairs[i + 1].trim());
            }
        }
        return map;
    }
}
```

### Explanation:

1. **Maintain Key Order**:
   - Use `LinkedHashMap` and `LinkedHashSet` instead of `HashMap` and `HashSet` to maintain the insertion order of keys.

2. **Update Extract Keys Method**:
   - `extractKeys`: This method now accepts a `Set<String>` which can be a `LinkedHashSet` to maintain order.

3. **Update Parse Key-Value Pairs Method**:
   - `parseKeyValuePairs`: This method now uses a `LinkedHashMap` to maintain the order of key-value pairs.

### Sending the Request Through Postman

1. **Set Request Type and URL**:
   - Set the request type to `POST`.
   - Enter the URL: `http://localhost:8080/api/query/execute`.

2. **Set Up the Body**:
   - Go to the `Body` tab.
   - Select `raw`.
   - Select `JSON` from the dropdown menu.
   - Enter the JSON body.

#### Example JSON Body:
```json
{
    "query": "SELECT * FROM your_table",
    "outputFilePath": "output.xlsx",
    "extractionColumns": ["column1", "column2"],
    "separatorRegex": "-"
}
```

3. **Send the Request**:
   - Click `Send`.
   - Check the response section to see the server's response.

This modification ensures the fields are extracted and ordered correctly in the output file.
Certainly! Here is the entire refactored Spring Boot application in one go:

### 1. `Application.java`

This is the main class to bootstrap the Spring Boot application.

```java
package com.example.dbqueryexecutor;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class Application {
    public static void main(String[] args) {
        SpringApplication.run(Application.class, args);
    }
}
```

### 2. `YourEntity.java`

This class represents the table in the database.

```java
package com.example.dbqueryexecutor.model;

import javax.persistence.*;

@Entity
@Table(name = "your_table")
public class YourEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "column1")
    private String column1;

    @Column(name = "column2")
    private String column2;

    // Add other columns as needed

    // Getters and setters
    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public String getColumn1() {
        return column1;
    }

    public void setColumn1(String column1) {
        this.column1 = column1;
    }

    public String getColumn2() {
        return column2;
    }

    public void setColumn2(String column2) {
        this.column2 = column2;
    }

    // Add other getters and setters as needed
}
```

### 3. `YourEntityRepository.java`

This interface handles the database operations.

```java
package com.example.dbqueryexecutor.repository;

import com.example.dbqueryexecutor.model.YourEntity;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

@Repository
public interface YourEntityRepository extends JpaRepository<YourEntity, Long> {
    // Define custom query methods if needed
}
```

### 4. `DatabaseQueryService.java`

This service executes the query and writes the results to an Excel file.

```java
package com.example.dbqueryexecutor.service;

import com.example.dbqueryexecutor.model.YourEntity;
import com.example.dbqueryexecutor.repository.YourEntityRepository;
import org.apache.poi.ss.usermodel.Row;
import org.apache.poi.ss.usermodel.Sheet;
import org.apache.poi.ss.usermodel.Workbook;
import org.apache.poi.xssf.usermodel.XSSFWorkbook;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import javax.persistence.EntityManager;
import javax.persistence.Query;
import javax.transaction.Transactional;
import java.io.FileOutputStream;
import java.io.IOException;
import java.util.*;

@Service
public class DatabaseQueryService {

    @Autowired
    private YourEntityRepository yourEntityRepository;

    @Autowired
    private EntityManager entityManager;

    @Transactional
    public void executeQueryAndWriteToExcel(String queryString, String outputFilePath, List<String> extractionColumns, String separatorRegex) {
        try (Workbook workbook = new XSSFWorkbook()) {
            Sheet sheet = workbook.createSheet("Query Results");

            // Execute the query dynamically using EntityManager
            Query query = entityManager.createNativeQuery(queryString, YourEntity.class);
            List<YourEntity> resultList = query.getResultList();

            // Get column names dynamically
            Map<String, Integer> headerIndexes = new LinkedHashMap<>();
            Row headerRow = sheet.createRow(0);
            int headerIndex = 0;

            for (String column : extractionColumns) {
                headerRow.createCell(headerIndex).setCellValue(column);
                headerIndexes.put(column, headerIndex++);
            }

            // Extracted keys in order
            Map<String, LinkedHashSet<String>> columnKeysMap = new LinkedHashMap<>();
            for (String column : extractionColumns) {
                columnKeysMap.put(column, new LinkedHashSet<>());
            }

            for (YourEntity entity : resultList) {
                extractKeys(entity, extractionColumns, columnKeysMap, separatorRegex);
            }

            // Write extracted key-value headers
            for (String column : extractionColumns) {
                for (String key : columnKeysMap.get(column)) {
                    headerIndexes.put(column + ":" + key, headerIndex);
                    headerRow.createCell(headerIndex++).setCellValue(key);
                }
            }

            // Fill in data
            int rowIndex = 1;
            for (YourEntity entity : resultList) {
                Row row = sheet.createRow(rowIndex++);
                int cellIndex = 0;

                for (String column : extractionColumns) {
                    String value = getEntityFieldValue(entity, column);
                    row.createCell(cellIndex++).setCellValue(value);

                    Map<String, String> keyValuePairs = parseKeyValuePairs(value, separatorRegex);
                    for (Map.Entry<String, String> entry : keyValuePairs.entrySet()) {
                        int index = headerIndexes.get(column + ":" + entry.getKey());
                        row.createCell(index).setCellValue(entry.getValue());
                    }
                }
            }

            try (FileOutputStream fileOut = new FileOutputStream(outputFilePath)) {
                workbook.write(fileOut);
            }

        } catch (IOException e) {
            e.printStackTrace();
        }
    }

    private void extractKeys(YourEntity entity, List<String> extractionColumns, Map<String, LinkedHashSet<String>> columnKeysMap, String separatorRegex) {
        for (String column : extractionColumns) {
            String value = getEntityFieldValue(entity, column);
            if (value != null && !value.isEmpty()) {
                String[] pairs = value.split(separatorRegex);
                for (int i = 0; i < pairs.length - 1; i += 2) {
                    columnKeysMap.get(column).add(pairs[i].trim());
                }
            }
        }
    }

    private Map<String, String> parseKeyValuePairs(String text, String separatorRegex) {
        Map<String, String> map = new LinkedHashMap<>();
        if (text != null && !text.isEmpty()) {
            String[] pairs = text.split(separatorRegex);
            for (int i = 0; i < pairs.length - 1; i += 2) {
                map.put(pairs[i].trim(), pairs[i + 1].trim());
            }
        }
        return map;
    }

    private String getEntityFieldValue(YourEntity entity, String fieldName) {
        try {
            return (String) YourEntity.class.getDeclaredField(fieldName).get(entity);
        } catch (NoSuchFieldException | IllegalAccessException e) {
            e.printStackTrace();
            return null;
        }
    }
}
```

### 5. `DatabaseQueryController.java`

This controller handles the incoming HTTP requests.

```java
package com.example.dbqueryexecutor.controller;

import com.example.dbqueryexecutor.service.DatabaseQueryService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/query")
public class DatabaseQueryController {

    @Autowired
    private DatabaseQueryService databaseQueryService;

    @PostMapping("/execute")
    public String executeQueryAndWriteToExcel(@RequestBody QueryRequest queryRequest) {
        databaseQueryService.executeQueryAndWriteToExcel(
                queryRequest.getQuery(),
                queryRequest.getOutputFilePath(),
                queryRequest.getExtractionColumns(),
                queryRequest.getSeparatorRegex()
        );
        return "Query executed and results written to Excel.";
    }
}
```

### 6. `QueryRequest.java`

This class represents the request body for the query execution.

```java
package com.example.dbqueryexecutor.controller;

import java.util.List;

public class QueryRequest {
    private String query;
    private String outputFilePath;
    private List<String> extractionColumns;
    private String separatorRegex;

    // Getters and setters

    public String getQuery() {
        return query;
    }

    public void setQuery(String query) {
        this.query = query;
    }

    public String getOutputFilePath() {
        return outputFilePath;
    }

    public void setOutputFilePath(String outputFilePath) {
        this.outputFilePath = outputFilePath;
    }

    public List<String> getExtractionColumns() {
        return extractionColumns;
    }

    public void setExtractionColumns(List<String> extractionColumns) {
        this.extractionColumns = extractionColumns;
    }

    public String getSeparatorRegex() {
        return separatorRegex;
    }

    public void setSeparatorRegex(String separatorRegex) {
        this.separatorRegex = separatorRegex;
    }
}
```

### 7. `application.properties`

Configure the database connection settings in this file.

```properties
# Database connection settings
spring.datasource.url=jdbc:mysql://localhost:3306/your_database_name
spring.datasource.username=your_database_username
spring.datasource.password=your_database_password
spring.datasource.driver-class-name=com.mysql.cj.jdbc.Driver

# JPA settings
spring.jpa.hibernate.ddl-auto=update
spring.jpa.show-sql=true
spring.jpa.properties.hibernate.dialect=org.hibernate.dialect.MySQL8Dialect
```

### 8. `pom.xml`

Ensure you have the correct dependencies in your `pom.xml`.

```xml
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://www.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.example</groupId>
    <artifactId>db-query-executor</artifactId>
    <version>1.0.0</version>
    <packaging>jar</packaging>

    <parent>
        <groupId>org.springframework.boot




src
└── main
    ├── java
    │   └── com
    │       └── example
    │           └── dbqueryexecutor
    │               ├── Application.java
    │               ├── controller
    │               │   ├── DatabaseQueryController.java
    │               │   └── QueryRequest.java
    │               ├── model
    │               │   └── YourEntity.java
    │               ├── repository
    │               │   └── YourEntityRepository.java
    │               └── service
    │                   └── DatabaseQueryService.java
    └── resources
        ├── application.properties



Here is the complete code for the Spring Boot application configured to use a Sybase database, including all necessary files and dependencies:

### `pom.xml`

Include the necessary dependencies:

```xml
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.example</groupId>
    <artifactId>db-query-executor</artifactId>
    <version>1.0.0</version>
    <packaging>jar</packaging>

    <parent>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-parent</artifactId>
        <version>2.7.0</version>
        <relativePath/>
    </parent>

    <properties>
        <java.version>11</java.version>
    </properties>

    <dependencies>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-data-jpa</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-web</artifactId>
        </dependency>
        <dependency>
            <groupId>com.sybase.jdbc4</groupId>
            <artifactId>jconn4</artifactId>
            <version>7.0</version>
            <scope>runtime</scope>
        </dependency>
        <dependency>
            <groupId>org.apache.poi</groupId>
            <artifactId>poi-ooxml</artifactId>
            <version>5.2.3</version>
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
```

### `application.properties`

Update the database connection settings for Sybase:

```properties
# Database connection settings
spring.datasource.url=jdbc:sybase:Tds:localhost:5000/your_database_name
spring.datasource.username=your_database_username
spring.datasource.password=your_database_password
spring.datasource.driver-class-name=com.sybase.jdbc4.jdbc.SybDriver

# JPA settings
spring.jpa.hibernate.ddl-auto=update
spring.jpa.show-sql=true
spring.jpa.properties.hibernate.dialect=org.hibernate.dialect.SybaseASE15Dialect
```

### Project Structure

1. **Application.java**

```java
package com.example.dbqueryexecutor;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class Application {
    public static void main(String[] args) {
        SpringApplication.run(Application.class, args);
    }
}
```

2. **YourEntity.java**

```java
package com.example.dbqueryexecutor.model;

import javax.persistence.*;

@Entity
@Table(name = "your_table")
public class YourEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "column1")
    private String column1;

    @Column(name = "column2")
    private String column2;

    // Add other columns as needed

    // Getters and setters
    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public String getColumn1() {
        return column1;
    }

    public void setColumn1(String column1) {
        this.column1 = column1;
    }

    public String getColumn2() {
        return column2;
    }

    public void setColumn2(String column2) {
        this.column2 = column2;
    }

    // Add other getters and setters as needed
}
```

3. **YourEntityRepository.java**

```java
package com.example.dbqueryexecutor.repository;

import com.example.dbqueryexecutor.model.YourEntity;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

@Repository
public interface YourEntityRepository extends JpaRepository<YourEntity, Long> {
    // Define custom query methods if needed
}
```

4. **DatabaseQueryService.java**

```java
package com.example.dbqueryexecutor.service;

import com.example.dbqueryexecutor.model.YourEntity;
import com.example.dbqueryexecutor.repository.YourEntityRepository;
import org.apache.poi.ss.usermodel.Row;
import org.apache.poi.ss.usermodel.Sheet;
import org.apache.poi.ss.usermodel.Workbook;
import org.apache.poi.xssf.usermodel.XSSFWorkbook;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import javax.persistence.EntityManager;
import javax.persistence.Query;
import javax.transaction.Transactional;
import java.io.FileOutputStream;
import java.io.IOException;
import java.util.*;

@Service
public class DatabaseQueryService {

    @Autowired
    private YourEntityRepository yourEntityRepository;

    @Autowired
    private EntityManager entityManager;

    @Transactional
    public void executeQueryAndWriteToExcel(String queryString, String outputFilePath, List<String> extractionColumns, String separatorRegex) {
        try (Workbook workbook = new XSSFWorkbook()) {
            Sheet sheet = workbook.createSheet("Query Results");

            // Execute the query dynamically using EntityManager
            Query query = entityManager.createNativeQuery(queryString, YourEntity.class);
            List<YourEntity> resultList = query.getResultList();

            // Get column names dynamically
            Map<String, Integer> headerIndexes = new LinkedHashMap<>();
            Row headerRow = sheet.createRow(0);
            int headerIndex = 0;

            for (String column : extractionColumns) {
                headerRow.createCell(headerIndex).setCellValue(column);
                headerIndexes.put(column, headerIndex++);
            }

            // Extracted keys in order
            Map<String, LinkedHashSet<String>> columnKeysMap = new LinkedHashMap<>();
            for (String column : extractionColumns) {
                columnKeysMap.put(column, new LinkedHashSet<>());
            }

            for (YourEntity entity : resultList) {
                extractKeys(entity, extractionColumns, columnKeysMap, separatorRegex);
            }

            // Write extracted key-value headers
            for (String column : extractionColumns) {
                for (String key : columnKeysMap.get(column)) {
                    headerIndexes.put(column + ":" + key, headerIndex);
                    headerRow.createCell(headerIndex++).setCellValue(key);
                }
            }

            // Fill in data
            int rowIndex = 1;
            for (YourEntity entity : resultList) {
                Row row = sheet.createRow(rowIndex++);
                int cellIndex = 0;

                for (String column : extractionColumns) {
                    String value = getEntityFieldValue(entity, column);
                    row.createCell(cellIndex++).setCellValue(value);

                    Map<String, String> keyValuePairs = parseKeyValuePairs(value, separatorRegex);
                    for (Map.Entry<String, String> entry : keyValuePairs.entrySet()) {
                        int index = headerIndexes.get(column + ":" + entry.getKey());
                        row.createCell(index).setCellValue(entry.getValue());
                    }
                }
            }

            try (FileOutputStream fileOut = new FileOutputStream(outputFilePath)) {
                workbook.write(fileOut);
            }

        } catch (IOException e) {
            e.printStackTrace();
        }
    }

    private void extractKeys(YourEntity entity, List<String> extractionColumns, Map<String, LinkedHashSet<String>> columnKeysMap, String separatorRegex) {
        for (String column : extractionColumns) {
            String value = getEntityFieldValue(entity, column);
            if (value != null && !value.isEmpty()) {
                String[] pairs = value.split(separatorRegex);
                for (int i = 0; i < pairs.length - 1; i += 2) {
                    columnKeysMap.get(column).add(pairs[i].trim());
                }
            }
        }
    }

    private Map<String, String> parseKeyValuePairs(String text, String separatorRegex) {
        Map<String, String> map = new LinkedHashMap<>();
        if (text != null && !text.isEmpty()) {
            String[] pairs = text.split(separatorRegex);
            for (int i = 0; i < pairs.length - 1; i += 2) {
                map.put(pairs[i].trim(), pairs[i + 1].trim());
            }
        }
        return map;
    }

    private String getEntityFieldValue(YourEntity entity, String fieldName) {
        try {
            return (String) YourEntity.class.getDeclaredField(fieldName).get(entity);
        } catch (NoSuchFieldException | IllegalAccessException e) {
            e.printStackTrace();
            return null;
        }
    }
}
```

5. **DatabaseQueryController.java**

```java
package com.example.dbqueryexecutor.controller;

import com.example.dbqueryexecutor.service.DatabaseQueryService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/query")
public class DatabaseQueryController {

    @Autowired
    private DatabaseQueryService databaseQueryService;

    @PostMapping("/execute")
    public String executeQueryAndWriteToExcel(@RequestBody QueryRequest queryRequest)

Let's complete the `DatabaseQueryController.java` and add the missing `QueryRequest.java` class to ensure the full code is provided:

### DatabaseQueryController.java

```java
package com.example.dbqueryexecutor.controller;

import com.example.dbqueryexecutor.service.DatabaseQueryService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/query")
public class DatabaseQueryController {

    @Autowired
    private DatabaseQueryService databaseQueryService;

    @PostMapping("/execute")
    public String executeQueryAndWriteToExcel(@RequestBody QueryRequest queryRequest) {
        databaseQueryService.executeQueryAndWriteToExcel(
                queryRequest.getQueryString(),
                queryRequest.getOutputFilePath(),
                queryRequest.getExtractionColumns(),
                queryRequest.getSeparatorRegex()
        );
        return "Query executed and results written to Excel file.";
    }
}
```

### QueryRequest.java

```java
package com.example.dbqueryexecutor.controller;

import java.util.List;

public class QueryRequest {

    private String queryString;
    private String outputFilePath;
    private List<String> extractionColumns;
    private String separatorRegex;

    // Getters and setters
    public String getQueryString() {
        return queryString;
    }

    public void setQueryString(String queryString) {
        this.queryString = queryString;
    }

    public String getOutputFilePath() {
        return outputFilePath;
    }

    public void setOutputFilePath(String outputFilePath) {
        this.outputFilePath = outputFilePath;
    }

    public List<String> getExtractionColumns() {
        return extractionColumns;
    }

    public void setExtractionColumns(List<String> extractionColumns) {
        this.extractionColumns = extractionColumns;
    }

    public String getSeparatorRegex() {
        return separatorRegex;
    }

    public void setSeparatorRegex(String separatorRegex) {
        this.separatorRegex = separatorRegex;
    }
}
```

### Summary

Here is a summary of the files included in the project:

1. **pom.xml**
2. **application.properties**
3. **Application.java**
4. **YourEntity.java**
5. **YourEntityRepository.java**
6. **DatabaseQueryService.java**
7. **DatabaseQueryController.java**
8. **QueryRequest.java**

This completes the full code for the Spring Boot application configured to use a Sybase database. Let me know if you need further assistance or modifications.


Sure, I'll simplify the code by removing the AWS Secrets Manager integration and the JPA components, since writing to the database is not required. The new version will focus only on reading from the database and writing the results to an Excel file.

### Project Structure

```
db-query-executor/
│
├── src/main/java/com/example/dbqueryexecutor/
│   ├── Application.java
│   ├── controller/
│   │   ├── DatabaseQueryController.java
│   │   └── QueryRequest.java
│   └── service/
│       └── DatabaseQueryService.java
│
├── src/main/resources/
│   ├── application.properties
│
├── pom.xml
│
└── README.md
```

### `pom.xml`

Include the necessary dependencies:

```xml
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://www.w3.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.example</groupId>
    <artifactId>db-query-executor</artifactId>
    <version>1.0.0</version>
    <packaging>jar</packaging>

    <parent>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-parent</artifactId>
        <version>2.7.0</version>
        <relativePath/>
    </parent>

    <properties>
        <java.version>11</java.version>
    </properties>

    <dependencies>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-data-jpa</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-web</artifactId>
        </dependency>
        <dependency>
            <groupId>com.sybase.jdbc4</groupId>
            <artifactId>jconn4</artifactId>
            <version>7.0</version>
            <scope>runtime</scope>
        </dependency>
        <dependency>
            <groupId>org.apache.poi</groupId>
            <artifactId>poi-ooxml</artifactId>
            <version>5.2.3</version>
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
```

### `application.properties`

Update the database connection settings for Sybase:

```properties
# Database connection settings
spring.datasource.url=jdbc:sybase:Tds:localhost:5000/your_database_name
spring.datasource.username=your_database_username
spring.datasource.password=your_database_password
spring.datasource.driver-class-name=com.sybase.jdbc4.jdbc.SybDriver
```

### `Application.java`

```java
package com.example.dbqueryexecutor;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class Application {
    public static void main(String[] args) {
        SpringApplication.run(Application.class, args);
    }
}
```

### `QueryRequest.java`

```java
package com.example.dbqueryexecutor.controller;

import java.util.List;

public class QueryRequest {
    private String query;
    private String outputFilePath;
    private List<String> extractionColumns;
    private String separatorRegex;

    // Getters and setters
    public String getQuery() {
        return query;
    }

    public void setQuery(String query) {
        this.query = query;
    }

    public String getOutputFilePath() {
        return outputFilePath;
    }

    public void setOutputFilePath(String outputFilePath) {
        this.outputFilePath = outputFilePath;
    }

    public List<String> getExtractionColumns() {
        return extractionColumns;
    }

    public void setExtractionColumns(List<String> extractionColumns) {
        this.extractionColumns = extractionColumns;
    }

    public String getSeparatorRegex() {
        return separatorRegex;
    }

    public void setSeparatorRegex(String separatorRegex) {
        this.separatorRegex = separatorRegex;
    }
}
```

### `DatabaseQueryController.java`

```java
package com.example.dbqueryexecutor.controller;

import com.example.dbqueryexecutor.service.DatabaseQueryService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/query")
public class DatabaseQueryController {

    @Autowired
    private DatabaseQueryService databaseQueryService;

    @PostMapping("/execute")
    public ResponseEntity<String> executeQuery(@RequestBody QueryRequest request) {
        databaseQueryService.executeQueryAndWriteToExcel(
                request.getQuery(),
                request.getOutputFilePath(),
                request.getExtractionColumns(),
                request.getSeparatorRegex()
        );
        return ResponseEntity.ok("Query executed and results written to " + request.getOutputFilePath());
    }
}
```

### `DatabaseQueryService.java`

```java
package com.example.dbqueryexecutor.service;

import org.apache.poi.ss.usermodel.Row;
import org.apache.poi.ss.usermodel.Sheet;
import org.apache.poi.ss.usermodel.Workbook;
import org.apache.poi.xssf.usermodel.XSSFWorkbook;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.stereotype.Service;

import javax.annotation.PostConstruct;
import java.io.FileOutputStream;
import java.io.IOException;
import java.sql.*;
import java.util.*;

@Service
public class DatabaseQueryService {

    @Value("${spring.datasource.url}")
    private String jdbcUrl;

    @Value("${spring.datasource.username}")
    private String jdbcUsername;

    @Value("${spring.datasource.password}")
    private String jdbcPassword;

    private DriverManagerDataSource dataSource;

    @PostConstruct
    public void initialize() {
        dataSource = new DriverManagerDataSource();
        dataSource.setUrl(jdbcUrl);
        dataSource.setUsername(jdbcUsername);
        dataSource.setPassword(jdbcPassword);
    }

    public void executeQueryAndWriteToExcel(String query, String outputFilePath, List<String> extractionColumns, String separatorRegex) {
        try (Connection connection = dataSource.getConnection();
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
                    extractKeys(resultSet.getString(columnIndex), columnKeysMap.get(column), separatorRegex);
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
                    Map<String, String> keyValuePairs = parseKeyValuePairs(resultSet.getString(columnIndex), separatorRegex);
                    for (Map.Entry<String, String> entry : keyValuePairs.entrySet()) {
                        int index = headerIndexes.get(column + ":" + entry.getKey());
                        row.createCell(index).setCellValue(entry.getValue());
                    }
                }
            }

            try (FileOutputStream fileOut = new FileOutputStream(outputFilePath)) {
                workbook


I apologize for the abrupt end. Let's continue from where we left off.

### `DatabaseQueryService.java` (continued)

Complete the `DatabaseQueryService` class by adding the remaining part of the `parseKeyValuePairs` method and ensuring all necessary imports are included:

```java
package com.example.dbqueryexecutor.service;

import org.apache.poi.ss.usermodel.Row;
import org.apache.poi.ss.usermodel.Sheet;
import org.apache.poi.ss.usermodel.Workbook;
import org.apache.poi.xssf.usermodel.XSSFWorkbook;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.stereotype.Service;

import javax.annotation.PostConstruct;
import java.io.FileOutputStream;
import java.io.IOException;
import java.sql.*;
import java.util.*;

@Service
public class DatabaseQueryService {

    @Value("${spring.datasource.url}")
    private String jdbcUrl;

    @Value("${spring.datasource.username}")
    private String jdbcUsername;

    @Value("${spring.datasource.password}")
    private String jdbcPassword;

    private DriverManagerDataSource dataSource;

    @PostConstruct
    public void initialize() {
        dataSource = new DriverManagerDataSource();
        dataSource.setUrl(jdbcUrl);
        dataSource.setUsername(jdbcUsername);
        dataSource.setPassword(jdbcPassword);
    }

    public void executeQueryAndWriteToExcel(String query, String outputFilePath, List<String> extractionColumns, String separatorRegex) {
        try (Connection connection = dataSource.getConnection();
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
                    extractKeys(resultSet.getString(columnIndex), columnKeysMap.get(column), separatorRegex);
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
                    Map<String, String> keyValuePairs = parseKeyValuePairs(resultSet.getString(columnIndex), separatorRegex);
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

    private void extractKeys(String text, Set<String> keys, String separatorRegex) {
        if (text != null && !text.isEmpty()) {
            String[] pairs = text.split(separatorRegex);
            for (int i = 0; i < pairs.length - 1; i += 2) {
                keys.add(pairs[i].trim());
            }
        }
    }

    private Map<String, String> parseKeyValuePairs(String text, String separatorRegex) {
        Map<String, String> map = new HashMap<>();
        if (text != null && !text.isEmpty()) {
            String[] pairs = text.split(separatorRegex);
            for (int i = 0; i < pairs.length - 1; i += 2) {
                map.put(pairs[i].trim(), pairs[i + 1].trim());
            }
        }
        return map;
    }
}
```

### Project Structure Recap

Ensure your project structure looks like this:

```
db-query-executor/
│
├── src/main/java/com/example/dbqueryexecutor/
│   ├── Application.java
│   ├── controller/
│   │   ├── DatabaseQueryController.java
│   │   └── QueryRequest.java
│   └── service/
│       └── DatabaseQueryService.java
│
├── src/main/resources/
│   └── application.properties
│
├── pom.xml
│
└── README.md
```

### Running the Project

1. **Clone or Create the Project Directory**: Create a new directory for the project and navigate into it.

    ```sh
    mkdir db-query-executor
    cd db-query-executor
    ```

2. **Create the Maven Project**: Use the following command to create a new Maven project.

    ```sh
    mvn archetype:generate -DgroupId=com.example -DartifactId=db-query-executor -DarchetypeArtifactId=maven-archetype-quickstart -DinteractiveMode=false
    cd db-query-executor
    ```

3. **Update the `pom.xml`**: Replace the content of the `pom.xml` with the provided content.

4. **Create the Project Structure**: Create the necessary directories and files according to the provided project structure.

    ```sh
    mkdir -p src/main/java/com/example/dbqueryexecutor/{controller,service}
    mkdir -p src/main/resources
    touch src/main/resources/application.properties
    touch src/main/java/com/example/dbqueryexecutor/Application.java
    touch src/main/java/com/example/dbqueryexecutor/controller/{DatabaseQueryController.java,QueryRequest.java}
    touch src/main/java/com/example/dbqueryexecutor/service/DatabaseQueryService.java
    ```

5. **Add the Provided Code**: Copy and paste the provided code into the respective files.

6. **Configure `application.properties`**: Update the `application.properties` file with your Sybase database connection details.

7. **Add Sybase JDBC Driver**: Ensure the Sybase JDBC driver (`jconn4.jar`) is available in your local Maven repository or add it manually.

    ```sh
    mvn install:install-file -Dfile=path/to/jconn4.jar -DgroupId=com.sybase.jdbc4 -DartifactId=jconn4 -Dversion=7.0 -Dpackaging=jar
    ```

8. **Build the Project**: Use Maven to build the project.

    ```sh
    mvn clean install
    ```

9. **Run the Application**: Use Maven to run the Spring Boot application.

    ```sh
    mvn spring-boot:run
    ```

### Testing the API

1. **Postman**: To test the API endpoints, you can use Postman to send HTTP requests. For example, to test the `executeQuery` endpoint:

    - Set the request type to `POST`.
    - Set the URL to `http://localhost:8080/query/execute`.
    - Set the request body to `raw` and choose `JSON` as the format.
    - Provide a JSON body similar to:

    ```json
    {
        "query": "SELECT * FROM your_table",
        "outputFilePath": "/path/to/output.xlsx",
        "extractionColumns": ["column1", "column2"],
        "separatorRegex": "-"
    }
    ```

By following these steps, you should be able to run the project and test its functionality. If you encounter any issues, make sure to check the logs for errors and ensure all configurations are correctly set.


To ensure the extracted fields are in the correct order, you need to maintain the order of columns and keys as specified in your input. Here's a modified version of the code to ensure the extracted fields maintain their specified order.

### Code Changes to Ensure Order of Extracted Fields

#### `DatabaseQueryService.java`

Make the following adjustments to ensure extracted keys are in the specified order.

```java
package com.example.dbqueryexecutor.service;

import org.apache.poi.ss.usermodel.Row;
import org.apache.poi.ss.usermodel.Sheet;
import org.apache.poi.ss.usermodel.Workbook;
import org.apache.poi.xssf.usermodel.XSSFWorkbook;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.stereotype.Service;

import javax.annotation.PostConstruct;
import java.io.FileOutputStream;
import java.io.IOException;
import java.sql.*;
import java.util.*;

@Service
public class DatabaseQueryService {

    @Value("${spring.datasource.url}")
    private String jdbcUrl;

    @Value("${spring.datasource.username}")
    private String jdbcUsername;

    @Value("${spring.datasource.password}")
    private String jdbcPassword;

    private DriverManagerDataSource dataSource;

    @PostConstruct
    public void initialize() {
        dataSource = new DriverManagerDataSource();
        dataSource.setUrl(jdbcUrl);
        dataSource.setUsername(jdbcUsername);
        dataSource.setPassword(jdbcPassword);
    }

    public void executeQueryAndWriteToExcel(String query, String outputFilePath, List<String> extractionColumns, String separatorRegex) {
        try (Connection connection = dataSource.getConnection();
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

            // Using LinkedHashMap to preserve the order of keys
            Map<String, LinkedHashSet<String>> columnKeysMap = new LinkedHashMap<>();
            for (String column : extractionColumns) {
                columnKeysMap.put(column, new LinkedHashSet<>());
            }

            while (resultSet.next()) {
                for (String column : extractionColumns) {
                    int columnIndex = resultSet.findColumn(column);
                    extractKeys(resultSet.getString(columnIndex), columnKeysMap.get(column), separatorRegex);
                }
            }

            resultSet.beforeFirst();

            Row headerRow = sheet.createRow(0);
            int headerIndex = 0;
            Map<String, Integer> headerIndexes = new LinkedHashMap<>();

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
                    Map<String, String> keyValuePairs = parseKeyValuePairs(resultSet.getString(columnIndex), separatorRegex);
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

    private void extractKeys(String text, Set<String> keys, String separatorRegex) {
        if (text != null && !text.isEmpty()) {
            String[] pairs = text.split(separatorRegex);
            for (int i = 0; i < pairs.length - 1; i += 2) {
                keys.add(pairs[i].trim());
            }
        }
    }

    private Map<String, String> parseKeyValuePairs(String text, String separatorRegex) {
        Map<String, String> map = new LinkedHashMap<>();
        if (text != null && !text.isEmpty()) {
            String[] pairs = text.split(separatorRegex);
            for (int i = 0; i < pairs.length - 1; i += 2) {
                map.put(pairs[i].trim(), pairs[i + 1].trim());
            }
        }
        return map;
    }
}
```

### Explanation

1. **Using `LinkedHashSet` and `LinkedHashMap`**:
   - `LinkedHashSet` is used to maintain the order of keys as they are added.
   - `LinkedHashMap` is used to maintain the insertion order of the headers.

2. **Modifying `extractKeys` and `parseKeyValuePairs`**:
   - The methods are updated to use `LinkedHashMap` to ensure the order of keys is preserved.

3. **Header Index Mapping**:
   - The header indexes are stored in a `LinkedHashMap` to ensure the correct order of headers.

### Steps to Trigger the API Using Postman

1. **Open Postman**.
2. **Create a new POST request** with URL `http://localhost:8080/query/execute`.
3. **Set up the request body** with the following JSON:

    ```json
    {
        "query": "SELECT * FROM your_table",
        "outputFilePath": "output.xlsx",
        "extractionColumns": ["acc", "id", "as", "time"],
        "separatorRegex": "-"
    }
    ```

4. **Send the request** and verify the response. The response should indicate the query execution and Excel file creation.


To modify the code to get the database username, password, and URL through a JSON payload in a Postman request, we'll need to update the service and controller to accept these parameters. Here's the full code with the required changes.

### Project Structure

```
src/
├── main/
│   ├── java/
│   │   └── com/
│   │       └── example/
│   │           └── dbqueryexecutor/
│   │               ├── DbQueryExecutorApplication.java
│   │               ├── controller/
│   │               │   └── DatabaseQueryController.java
│   │               └── service/
│   │                   └── DatabaseQueryService.java
│   └── resources/
│       └── application.properties
```

### `application.properties`

Since we will be getting the database credentials through the request, no specific database properties are needed here.

```properties
# No database properties required
```

### `DbQueryExecutorApplication.java`

This is the main application class.

```java
package com.example.dbqueryexecutor;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class DbQueryExecutorApplication {

    public static void main(String[] args) {
        SpringApplication.run(DbQueryExecutorApplication.class, args);
    }
}
```

### `DatabaseQueryController.java`

The controller to handle the requests.

```java
package com.example.dbqueryexecutor.controller;

import com.example.dbqueryexecutor.service.DatabaseQueryService;
import com.fasterxml.jackson.annotation.JsonProperty;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/query")
public class DatabaseQueryController {

    @Autowired
    private DatabaseQueryService queryService;

    @PostMapping("/execute")
    public void executeQuery(@RequestBody QueryRequest queryRequest) {
        queryService.executeQueryAndWriteToExcel(
                queryRequest.getJdbcUrl(),
                queryRequest.getJdbcUsername(),
                queryRequest.getJdbcPassword(),
                queryRequest.getQuery(),
                queryRequest.getOutputFilePath(),
                queryRequest.getExtractionColumns(),
                queryRequest.getSeparatorRegex()
        );
    }

    public static class QueryRequest {
        @JsonProperty("jdbcUrl")
        private String jdbcUrl;

        @JsonProperty("jdbcUsername")
        private String jdbcUsername;

        @JsonProperty("jdbcPassword")
        private String jdbcPassword;

        @JsonProperty("query")
        private String query;

        @JsonProperty("outputFilePath")
        private String outputFilePath;

        @JsonProperty("extractionColumns")
        private List<String> extractionColumns;

        @JsonProperty("separatorRegex")
        private String separatorRegex;

        // Getters and setters
        public String getJdbcUrl() {
            return jdbcUrl;
        }

        public void setJdbcUrl(String jdbcUrl) {
            this.jdbcUrl = jdbcUrl;
        }

        public String getJdbcUsername() {
            return jdbcUsername;
        }

        public void setJdbcUsername(String jdbcUsername) {
            this.jdbcUsername = jdbcUsername;
        }

        public String getJdbcPassword() {
            return jdbcPassword;
        }

        public void setJdbcPassword(String jdbcPassword) {
            this.jdbcPassword = jdbcPassword;
        }

        public String getQuery() {
            return query;
        }

        public void setQuery(String query) {
            this.query = query;
        }

        public String getOutputFilePath() {
            return outputFilePath;
        }

        public void setOutputFilePath(String outputFilePath) {
            this.outputFilePath = outputFilePath;
        }

        public List<String> getExtractionColumns() {
            return extractionColumns;
        }

        public void setExtractionColumns(List<String> extractionColumns) {
            this.extractionColumns = extractionColumns;
        }

        public String getSeparatorRegex() {
            return separatorRegex;
        }

        public void setSeparatorRegex(String separatorRegex) {
            this.separatorRegex = separatorRegex;
        }
    }
}
```

### `DatabaseQueryService.java`

The service to execute the query and write the results to Excel.

```java
package com.example.dbqueryexecutor.service;

import org.apache.poi.ss.usermodel.Row;
import org.apache.poi.ss.usermodel.Sheet;
import org.apache.poi.ss.usermodel.Workbook;
import org.apache.poi.xssf.usermodel.XSSFWorkbook;
import org.springframework.stereotype.Service;

import java.io.FileOutputStream;
import java.io.IOException;
import java.sql.*;
import java.util.*;

@Service
public class DatabaseQueryService {

    public void executeQueryAndWriteToExcel(String jdbcUrl, String jdbcUsername, String jdbcPassword,
                                            String query, String outputFilePath, List<String> extractionColumns, String separatorRegex) {
        try (Connection connection = DriverManager.getConnection(jdbcUrl, jdbcUsername, jdbcPassword);
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

            Map<String, LinkedHashSet<String>> columnKeysMap = new LinkedHashMap<>();
            for (String column : extractionColumns) {
                columnKeysMap.put(column, new LinkedHashSet<>());
            }

            while (resultSet.next()) {
                for (String column : extractionColumns) {
                    int columnIndex = resultSet.findColumn(column);
                    extractKeys(resultSet.getString(columnIndex), columnKeysMap.get(column), separatorRegex);
                }
            }

            resultSet.beforeFirst();

            Row headerRow = sheet.createRow(0);
            int headerIndex = 0;
            Map<String, Integer> headerIndexes = new LinkedHashMap<>();

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
                    Map<String, String> keyValuePairs = parseKeyValuePairs(resultSet.getString(columnIndex), separatorRegex);
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

    private void extractKeys(String text, Set<String> keys, String separatorRegex) {
        if (text != null && !text.isEmpty()) {
            String[] pairs = text.split(separatorRegex);
            for (int i = 0; i < pairs.length - 1; i += 2) {
                keys.add(pairs[i].trim());
            }
        }
    }

    private Map<String, String> parseKeyValuePairs(String text, String separatorRegex) {
        Map<String, String> map = new LinkedHashMap<>();
        if (text != null && !text.isEmpty()) {
            String[] pairs = text.split(separatorRegex);
            for (int i = 0; i < pairs.length - 1; i += 2) {
                map.put(pairs[i].trim(), pairs[i + 1].trim());
            }
        }
        return map;
    }
}
```

### Steps to Trigger the API Using Postman

1. **Open Postman**.
2. **Create a new POST request** with URL `http://localhost:8080/query/execute`.
3. **Set up the request body** with the following JSON:

    ```json
    {
        "jdbcUrl": "jdbc:sybase:Tds:your_server_name:your_port/your_database",
        "jdbcUsername": "your_username",
        "jdbcPassword": "your_password",
        "query": "SELECT * FROM your_table",
        "outputFilePath": "output.xlsx",
        "extractionColumns": ["acc", "id", "as", "time"],
        "separatorRegex": "-"
    }
    ```

4. **Send the request** and verify the response. The response should indicate the query execution and Excel file creation.

### Summary

- The project structure includes a main application class, a controller, and a service.
- The database credentials, query, output file path, extraction columns, and separator regex are passed through the JSON request.
- The service executes the query and writes the results to an Excel file while preserving the order of extracted fields.

Including `QueryRequest` within the `DatabaseQueryController` was done to keep things simple. However, for better organization and maintainability, it's more appropriate to separate `QueryRequest` into its own file. Here's the revised project structure and the corresponding code:

### Revised Project Structure

```
db-query-executor/
├── src/
│   ├── main/
│   │   ├── java/
│   │   │   └── com/
│   │   │       └── example/
│   │   │           └── dbqueryexecutor/
│   │   │               ├── DbQueryExecutorApplication.java
│   │   │               ├── controller/
│   │   │               │   └── DatabaseQueryController.java
│   │   │               ├── model/
│   │   │               │   └── QueryRequest.java
│   │   │               └── service/
│   │   │                   └── DatabaseQueryService.java
│   ├── resources/
│   │   └── application.properties
└── pom.xml
```

### `DbQueryExecutorApplication.java`

```java
package com.example.dbqueryexecutor;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class DbQueryExecutorApplication {

    public static void main(String[] args) {
        SpringApplication.run(DbQueryExecutorApplication.class, args);
    }
}
```

### `controller/DatabaseQueryController.java`

```java
package com.example.dbqueryexecutor.controller;

import com.example.dbqueryexecutor.model.QueryRequest;
import com.example.dbqueryexecutor.service.DatabaseQueryService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/query")
public class DatabaseQueryController {

    @Autowired
    private DatabaseQueryService queryService;

    @PostMapping("/execute")
    public void executeQuery(@RequestBody QueryRequest queryRequest) {
        queryService.executeQueryAndWriteToExcel(
                queryRequest.getJdbcUrl(),
                queryRequest.getJdbcUsername(),
                queryRequest.getJdbcPassword(),
                queryRequest.getQuery(),
                queryRequest.getOutputFilePath(),
                queryRequest.getExtractionColumns(),
                queryRequest.getSeparatorRegex()
        );
    }
}
```

### `model/QueryRequest.java`

```java
package com.example.dbqueryexecutor.model;

import com.fasterxml.jackson.annotation.JsonProperty;

import java.util.List;

public class QueryRequest {

    @JsonProperty("jdbcUrl")
    private String jdbcUrl;

    @JsonProperty("jdbcUsername")
    private String jdbcUsername;

    @JsonProperty("jdbcPassword")
    private String jdbcPassword;

    @JsonProperty("query")
    private String query;

    @JsonProperty("outputFilePath")
    private String outputFilePath;

    @JsonProperty("extractionColumns")
    private List<String> extractionColumns;

    @JsonProperty("separatorRegex")
    private String separatorRegex;

    // Getters and setters
    public String getJdbcUrl() {
        return jdbcUrl;
    }

    public void setJdbcUrl(String jdbcUrl) {
        this.jdbcUrl = jdbcUrl;
    }

    public String getJdbcUsername() {
        return jdbcUsername;
    }

    public void setJdbcUsername(String jdbcUsername) {
        this.jdbcUsername = jdbcUsername;
    }

    public String getJdbcPassword() {
        return jdbcPassword;
    }

    public void setJdbcPassword(String jdbcPassword) {
        this.jdbcPassword = jdbcPassword;
    }

    public String getQuery() {
        return query;
    }

    public void setQuery(String query) {
        this.query = query;
    }

    public String getOutputFilePath() {
        return outputFilePath;
    }

    public void setOutputFilePath(String outputFilePath) {
        this.outputFilePath = outputFilePath;
    }

    public List<String> getExtractionColumns() {
        return extractionColumns;
    }

    public void setExtractionColumns(List<String> extractionColumns) {
        this.extractionColumns = extractionColumns;
    }

    public String getSeparatorRegex() {
        return separatorRegex;
    }

    public void setSeparatorRegex(String separatorRegex) {
        this.separatorRegex = separatorRegex;
    }
}
```

### `service/DatabaseQueryService.java`

```java
package com.example.dbqueryexecutor.service;

import org.apache.poi.ss.usermodel.Row;
import org.apache.poi.ss.usermodel.Sheet;
import org.apache.poi.ss.usermodel.Workbook;
import org.apache.poi.xssf.usermodel.XSSFWorkbook;
import org.springframework.stereotype.Service;

import java.io.FileOutputStream;
import java.io.IOException;
import java.sql.*;
import java.util.*;

@Service
public class DatabaseQueryService {

    public void executeQueryAndWriteToExcel(String jdbcUrl, String jdbcUsername, String jdbcPassword,
                                            String query, String outputFilePath, List<String> extractionColumns, String separatorRegex) {
        try (Connection connection = DriverManager.getConnection(jdbcUrl, jdbcUsername, jdbcPassword);
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

            Map<String, LinkedHashSet<String>> columnKeysMap = new LinkedHashMap<>();
            for (String column : extractionColumns) {
                columnKeysMap.put(column, new LinkedHashSet<>());
            }

            while (resultSet.next()) {
                for (String column : extractionColumns) {
                    int columnIndex = resultSet.findColumn(column);
                    extractKeys(resultSet.getString(columnIndex), columnKeysMap.get(column), separatorRegex);
                }
            }

            resultSet.beforeFirst();

            Row headerRow = sheet.createRow(0);
            int headerIndex = 0;
            Map<String, Integer> headerIndexes = new LinkedHashMap<>();

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
                    Map<String, String> keyValuePairs = parseKeyValuePairs(resultSet.getString(columnIndex), separatorRegex);
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

    private void extractKeys(String text, Set<String> keys, String separatorRegex) {
        if (text != null && !text.isEmpty()) {
            String[] pairs = text.split(separatorRegex);
            for (int i = 0; i < pairs.length - 1; i += 2) {
                keys.add(pairs[i].trim());
            }
        }
    }

    private Map<String, String> parseKeyValuePairs(String text, String separatorRegex) {
        Map<String, String> map = new LinkedHashMap<>();
        if (text != null && !text.isEmpty()) {
            String[] pairs = text.split(separatorRegex);
            for (int i = 0; i < pairs.length - 1; i += 2) {
                map.put(pairs[i].trim(), pairs[i + 1].trim());
            }
        }
        return map;
    }
}
```

### `application.properties`

No changes are required in this file as we are now providing the database credentials and other parameters through a JSON payload.

### Steps to Trigger the API Using Postman

1. **Open Postman**.
2. **Create a new POST request** with URL `http://localhost:8080/query/execute`.
3. **Set up the request body** with the following JSON:

    ```json
    {
        "jdbcUrl": "jdbc:sybase:Tds:your_server_name:your_port/your_database",
        "jdbcUsername": "your_username",
        "jdbcPassword": "your_password",
        "query": "SELECT * FROM your_table",
        "outputFilePath": "output.xlsx",
        "extractionColumns": ["acc", "id", "as", "time"],
        "separatorRegex": "-"
    }
    ```

4. **Send the request** and verify the response. The response should indicate the query execution and Excel file creation.

To fix the error "Failed to configure a datasource url" when dynamically setting the JDBC URL, username, and password through Postman, we need to ensure that the `DatabaseQueryService` properly uses these parameters without relying on static configuration in `application.properties`.

Here’s the updated code, including dynamic database credentials:

### Project Structure

```
db-query-executor/
├── src/
│   ├── main/
│   │   ├── java/
│   │   │   └── com/
│   │   │       └── example/
│   │   │           └── dbqueryexecutor/
│   │   │               ├── DbQueryExecutorApplication.java
│   │   │               ├── controller/
│   │   │               │   └── DatabaseQueryController.java
│   │   │               ├── model/
│   │   │               │   └── QueryRequest.java
│   │   │               └── service/
│   │   │                   └── DatabaseQueryService.java
│   ├── resources/
│   │   └── application.properties
└── pom.xml
```

### `DbQueryExecutorApplication.java`

```java
package com.example.dbqueryexecutor;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class DbQueryExecutorApplication {

    public static void main(String[] args) {
        SpringApplication.run(DbQueryExecutorApplication.class, args);
    }
}
```

### `controller/DatabaseQueryController.java`

```java
package com.example.dbqueryexecutor.controller;

import com.example.dbqueryexecutor.model.QueryRequest;
import com.example.dbqueryexecutor.service.DatabaseQueryService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/query")
public class DatabaseQueryController {

    @Autowired
    private DatabaseQueryService queryService;

    @PostMapping("/execute")
    public void executeQuery(@RequestBody QueryRequest queryRequest) {
        queryService.executeQueryAndWriteToExcel(
                queryRequest.getJdbcUrl(),
                queryRequest.getJdbcUsername(),
                queryRequest.getJdbcPassword(),
                queryRequest.getQuery(),
                queryRequest.getOutputFilePath(),
                queryRequest.getExtractionColumns(),
                queryRequest.getSeparatorRegex()
        );
    }
}
```

### `model/QueryRequest.java`

```java
package com.example.dbqueryexecutor.model;

import com.fasterxml.jackson.annotation.JsonProperty;

import java.util.List;

public class QueryRequest {

    @JsonProperty("jdbcUrl")
    private String jdbcUrl;

    @JsonProperty("jdbcUsername")
    private String jdbcUsername;

    @JsonProperty("jdbcPassword")
    private String jdbcPassword;

    @JsonProperty("query")
    private String query;

    @JsonProperty("outputFilePath")
    private String outputFilePath;

    @JsonProperty("extractionColumns")
    private List<String> extractionColumns;

    @JsonProperty("separatorRegex")
    private String separatorRegex;

    // Getters and setters
    public String getJdbcUrl() {
        return jdbcUrl;
    }

    public void setJdbcUrl(String jdbcUrl) {
        this.jdbcUrl = jdbcUrl;
    }

    public String getJdbcUsername() {
        return jdbcUsername;
    }

    public void setJdbcUsername(String jdbcUsername) {
        this.jdbcUsername = jdbcUsername;
    }

    public String getJdbcPassword() {
        return jdbcPassword;
    }

    public void setJdbcPassword(String jdbcPassword) {
        this.jdbcPassword = jdbcPassword;
    }

    public String getQuery() {
        return query;
    }

    public void setQuery(String query) {
        this.query = query;
    }

    public String getOutputFilePath() {
        return outputFilePath;
    }

    public void setOutputFilePath(String outputFilePath) {
        this.outputFilePath = outputFilePath;
    }

    public List<String> getExtractionColumns() {
        return extractionColumns;
    }

    public void setExtractionColumns(List<String> extractionColumns) {
        this.extractionColumns = extractionColumns;
    }

    public String getSeparatorRegex() {
        return separatorRegex;
    }

    public void setSeparatorRegex(String separatorRegex) {
        this.separatorRegex = separatorRegex;
    }
}
```

### `service/DatabaseQueryService.java`

```java
package com.example.dbqueryexecutor.service;

import org.apache.poi.ss.usermodel.Row;
import org.apache.poi.ss.usermodel.Sheet;
import org.apache.poi.ss.usermodel.Workbook;
import org.apache.poi.xssf.usermodel.XSSFWorkbook;
import org.springframework.stereotype.Service;

import java.io.FileOutputStream;
import java.io.IOException;
import java.sql.*;
import java.util.*;

@Service
public class DatabaseQueryService {

    public void executeQueryAndWriteToExcel(
            String jdbcUrl, String jdbcUsername, String jdbcPassword,
            String query, String outputFilePath, List<String> extractionColumns, String separatorRegex) {
        try (Connection connection = DriverManager.getConnection(jdbcUrl, jdbcUsername, jdbcPassword);
             Statement statement = connection.createStatement(ResultSet.TYPE_SCROLL_INSENSITIVE, ResultSet.CONCUR_READ_ONLY);
             ResultSet resultSet = statement.executeQuery(query);
             Workbook workbook = new XSSFWorkbook()) {

            Class.forName("com.sybase.jdbc4.jdbc.SybDriver");
            Sheet sheet = workbook.createSheet("Query Results");

            ResultSetMetaData metaData = resultSet.getMetaData();
            int columnCount = metaData.getColumnCount();

            List<String> allColumns = new ArrayList<>();
            for (int i = 1; i <= columnCount; i++) {
                allColumns.add(metaData.getColumnName(i));
            }

            Map<String, LinkedHashSet<String>> columnKeysMap = new LinkedHashMap<>();
            for (String column : extractionColumns) {
                columnKeysMap.put(column, new LinkedHashSet<>());
            }

            while (resultSet.next()) {
                for (String column : extractionColumns) {
                    int columnIndex = resultSet.findColumn(column);
                    extractKeys(resultSet.getString(columnIndex), columnKeysMap.get(column), separatorRegex);
                }
            }

            resultSet.beforeFirst();

            Row headerRow = sheet.createRow(0);
            int headerIndex = 0;
            Map<String, Integer> headerIndexes = new LinkedHashMap<>();

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
                    Map<String, String> keyValuePairs = parseKeyValuePairs(resultSet.getString(columnIndex), separatorRegex);
                    for (Map.Entry<String, String> entry : keyValuePairs.entrySet()) {
                        int index = headerIndexes.get(column + ":" + entry.getKey());
                        row.createCell(index).setCellValue(entry.getValue());
                    }
                }
            }

            try (FileOutputStream fileOut = new FileOutputStream(outputFilePath)) {
                workbook.write(fileOut);
            }

        } catch (ClassNotFoundException e) {
            System.out.println("Sybase JDBC Driver not found.");
            e.printStackTrace();
        } catch (SQLException | IOException e) {
            e.printStackTrace();
        }
    }

    private void extractKeys(String text, Set<String> keys, String separatorRegex) {
        if (text != null && !text.isEmpty()) {
            String[] pairs = text.split(separatorRegex);
            for (int i = 0; i < pairs.length - 1; i += 2) {
                keys.add(pairs[i].trim());
            }
        }
    }

    private Map<String, String> parseKeyValuePairs(String text, String separatorRegex) {
        Map<String, String> map = new LinkedHashMap<>();
        if (text != null && !text.isEmpty()) {
            String[] pairs = text.split(separatorRegex);
            for (int i = 0; i < pairs.length - 1; i += 2) {
                map.put(pairs[i].trim(), pairs[i + 1].trim());
            }
        }
        return map;
    }
}
```

### `application.properties`

```properties
spring.datasource.driver-class-name=com.sybase.jdbc4.jdbc.SybDriver
```

### Steps to Trigger the API Using Postman

1. **Open Postman**.
2. **Create a new POST request** with URL `http://localhost:8080/query/execute`.
3. **Set up the request body** with the following JSON:

    ```json
    {
        "jdbcUrl": "jdbc:sybase:Tds:your_server_name:your_port/your_database",
        "jdbcUsername": "your_username",
        "jdbcPassword": "your_password",
        "query": "SELECT * FROM your_table",
        "outputFilePath": "output.xlsx",
        "extractionColumns": ["acc", "id", "as", "time"],
        "separatorRegex": "-"
    }
    ```

4. **Send the request** and verify the response. The response should indicate the query execution and Excel file creation.

By following this approach, you dynamically pass database credentials and other query parameters via Postman, ensuring they are used directly within the service without relying on static properties.

To pass the datasource URL, username, and password dynamically through JSON and still manage the datasource configuration in `application.properties`, you can use Spring Boot's support for dynamic properties. However, Spring Boot does not natively support changing `application.properties` at runtime directly from JSON requests.

Instead, you can create a custom configuration and manage the datasource manually. Here’s how you can achieve it:

### Step-by-Step Guide

1. **Modify the `application.properties`** to include basic configurations without database specifics:
   ```properties
   spring.main.allow-bean-definition-overriding=true
   spring.datasource.driver-class-name=com.sybase.jdbc4.jdbc.SybDriver
   ```

2. **Create a custom configuration for the DataSource**:

   ```java
   package com.example.dbqueryexecutor.config;

   import org.springframework.context.annotation.Bean;
   import org.springframework.context.annotation.Configuration;
   import org.springframework.jdbc.datasource.DriverManagerDataSource;

   import javax.sql.DataSource;

   @Configuration
   public class DataSourceConfig {

       @Bean
       public DataSource dataSource(String url, String username, String password) {
           DriverManagerDataSource dataSource = new DriverManagerDataSource();
           dataSource.setDriverClassName("com.sybase.jdbc4.jdbc.SybDriver");
           dataSource.setUrl(url);
           dataSource.setUsername(username);
           dataSource.setPassword(password);
           return dataSource;
       }
   }
   ```

3. **Update the `DatabaseQueryService`** to use the custom DataSource:

   ```java
   package com.example.dbqueryexecutor.service;

   import org.apache.poi.ss.usermodel.Row;
   import org.apache.poi.ss.usermodel.Sheet;
   import org.apache.poi.ss.usermodel.Workbook;
   import org.apache.poi.xssf.usermodel.XSSFWorkbook;
   import org.springframework.beans.factory.annotation.Autowired;
   import org.springframework.jdbc.datasource.DriverManagerDataSource;
   import org.springframework.stereotype.Service;

   import javax.sql.DataSource;
   import java.io.FileOutputStream;
   import java.io.IOException;
   import java.sql.*;
   import java.util.*;

   @Service
   public class DatabaseQueryService {

       @Autowired
       private DataSourceConfig dataSourceConfig;

       public void executeQueryAndWriteToExcel(
               String jdbcUrl, String jdbcUsername, String jdbcPassword,
               String query, String outputFilePath, List<String> extractionColumns, String separatorRegex) {

           DataSource dataSource = dataSourceConfig.dataSource(jdbcUrl, jdbcUsername, jdbcPassword);

           try (Connection connection = dataSource.getConnection();
                Statement statement = connection.createStatement(ResultSet.TYPE_SCROLL_INSENSITIVE, ResultSet.CONCUR_READ_ONLY);
                ResultSet resultSet = statement.executeQuery(query);
                Workbook workbook = new XSSFWorkbook()) {

               Class.forName("com.sybase.jdbc4.jdbc.SybDriver");
               Sheet sheet = workbook.createSheet("Query Results");

               ResultSetMetaData metaData = resultSet.getMetaData();
               int columnCount = metaData.getColumnCount();

               List<String> allColumns = new ArrayList<>();
               for (int i = 1; i <= columnCount; i++) {
                   allColumns.add(metaData.getColumnName(i));
               }

               Map<String, LinkedHashSet<String>> columnKeysMap = new LinkedHashMap<>();
               for (String column : extractionColumns) {
                   columnKeysMap.put(column, new LinkedHashSet<>());
               }

               while (resultSet.next()) {
                   for (String column : extractionColumns) {
                       int columnIndex = resultSet.findColumn(column);
                       extractKeys(resultSet.getString(columnIndex), columnKeysMap.get(column), separatorRegex);
                   }
               }

               resultSet.beforeFirst();

               Row headerRow = sheet.createRow(0);
               int headerIndex = 0;
               Map<String, Integer> headerIndexes = new LinkedHashMap<>();

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
                       Map<String, String> keyValuePairs = parseKeyValuePairs(resultSet.getString(columnIndex), separatorRegex);
                       for (Map.Entry<String, String> entry : keyValuePairs.entrySet()) {
                           int index = headerIndexes.get(column + ":" + entry.getKey());
                           row.createCell(index).setCellValue(entry.getValue());
                       }
                   }
               }

               try (FileOutputStream fileOut = new FileOutputStream(outputFilePath)) {
                   workbook.write(fileOut);
               }

           } catch (ClassNotFoundException e) {
               System.out.println("Sybase JDBC Driver not found.");
               e.printStackTrace();
           } catch (SQLException | IOException e) {
               e.printStackTrace();
           }
       }

       private void extractKeys(String text, Set<String> keys, String separatorRegex) {
           if (text != null && !text.isEmpty()) {
               String[] pairs = text.split(separatorRegex);
               for (int i = 0; i < pairs.length - 1; i += 2) {
                   keys.add(pairs[i].trim());
               }
           }
       }

       private Map<String, String> parseKeyValuePairs(String text, String separatorRegex) {
           Map<String, String> map = new LinkedHashMap<>();
           if (text != null && !text.isEmpty()) {
               String[] pairs = text.split(separatorRegex);
               for (int i = 0; i < pairs.length - 1; i += 2) {
                   map.put(pairs[i].trim(), pairs[i + 1].trim());
               }
           }
           return map;
       }
   }
   ```

4. **Modify `QueryRequest` to include database connection details**:
   ```java
   package com.example.dbqueryexecutor.model;

   import com.fasterxml.jackson.annotation.JsonProperty;

   import java.util.List;

   public class QueryRequest {

       @JsonProperty("jdbcUrl")
       private String jdbcUrl;

       @JsonProperty("jdbcUsername")
       private String jdbcUsername;

       @JsonProperty("jdbcPassword")
       private String jdbcPassword;

       @JsonProperty("query")
       private String query;

       @JsonProperty("outputFilePath")
       private String outputFilePath;

       @JsonProperty("extractionColumns")
       private List<String> extractionColumns;

       @JsonProperty("separatorRegex")
       private String separatorRegex;

       // Getters and setters
       public String getJdbcUrl() {
           return jdbcUrl;
       }

       public void setJdbcUrl(String jdbcUrl) {
           this.jdbcUrl = jdbcUrl;
       }

       public String getJdbcUsername() {
           return jdbcUsername;
       }

       public void setJdbcUsername(String jdbcUsername) {
           this.jdbcUsername = jdbcUsername;
       }

       public String getJdbcPassword() {
           return jdbcPassword;
       }

       public void setJdbcPassword(String jdbcPassword) {
           this.jdbcPassword = jdbcPassword;
       }

       public String getQuery() {
           return query;
       }

       public void setQuery(String query) {
           this.query = query;
       }

       public String getOutputFilePath() {
           return outputFilePath;
       }

       public void setOutputFilePath(String outputFilePath) {
           this.outputFilePath = outputFilePath;
       }

       public List<String> getExtractionColumns() {
           return extractionColumns;
       }

       public void setExtractionColumns(List<String> extractionColumns) {
           this.extractionColumns = extractionColumns;
       }

       public String getSeparatorRegex() {
           return separatorRegex;
       }

       public void setSeparatorRegex(String separatorRegex) {
           this.separatorRegex = separatorRegex;
       }
   }
   ```

5. **Update `DatabaseQueryController` to handle the new `QueryRequest`**:
   ```java
   package com.example.dbqueryexecutor.controller;

   import com.example.dbqueryexecutor.model.QueryRequest;
   import com.example.dbqueryexecutor.service.DatabaseQueryService;
   import org.springframework.beans.factory.annotation.Autowired;
   import org.springframework.web.bind.annotation.*;

   @RestController
   @RequestMapping("/query")
   public class DatabaseQueryController {

       @Autowired
       private DatabaseQueryService queryService;

       @PostMapping("/execute")
       public void executeQuery(@RequestBody QueryRequest queryRequest) {
           queryService.executeQueryAndWriteToExcel(
                   queryRequest.getJdbcUrl(),
                   queryRequest.getJdbcUsername(),
                   queryRequest.getJdbcPassword(),
                   queryRequest.getQuery(),
                   queryRequest.getOutputFilePath(),
                   queryRequest.getExtractionColumns(),
                   queryRequest.getSeparatorRegex()
           );
       }
   }
   ```

### Project Structure

The project structure should look like this:

```
db-query-executor/
├── src/
│   ├── main/
│   │   ├── java/
│   │   │   └── com/
│   │   │       └── example/
│   │   │           └── dbqueryexecutor/
│   │   │               ├── config/
│   │   │               │   └── DataSourceConfig.java
│   │   │               ├── controller/
│   │   │               │   └── DatabaseQueryController.java
│   │   │               ├── model/
│   │   │              
