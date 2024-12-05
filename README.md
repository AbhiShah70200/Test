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


Sure, here is the complete project structure for the Spring Boot application:

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
│   │   │               │   └── QueryRequest.java
│   │   │               ├── service/
│   │   │               │   └── DatabaseQueryService.java
│   │   │               └── DbQueryExecutorApplication.java
│   │   ├── resources/
│   │   │   ├── application.properties
│   │   │   └── logback-spring.xml (optional for logging configuration)
│   └── test/
│       └── java/
│           └── com/
│               └── example/
│                   └── dbqueryexecutor/
│                       ├── DatabaseQueryServiceTest.java
│                       └── DatabaseQueryControllerTest.java
└── pom.xml
```

### Explanation of the Project Structure

1. **src/main/java/com/example/dbqueryexecutor/config/**:
   - `DataSourceConfig.java`: Contains the configuration for the DataSource.

2. **src/main/java/com/example/dbqueryexecutor/controller/**:
   - `DatabaseQueryController.java`: REST controller that handles the query execution request.

3. **src/main/java/com/example/dbqueryexecutor/model/**:
   - `QueryRequest.java`: Model class representing the JSON request payload.

4. **src/main/java/com/example/dbqueryexecutor/service/**:
   - `DatabaseQueryService.java`: Service class that handles the business logic of executing the query and writing the results to an Excel file.

5. **src/main/java/com/example/dbqueryexecutor/**:
   - `DbQueryExecutorApplication.java`: The main Spring Boot application class.

6. **src/main/resources/**:
   - `application.properties`: Configuration file for the Spring Boot application.
   - `logback-spring.xml` (optional): Configuration for logging.

7. **src/test/java/com/example/dbqueryexecutor/**:
   - `DatabaseQueryServiceTest.java`: Unit tests for the `DatabaseQueryService` class.
   - `DatabaseQueryControllerTest.java`: Unit tests for the `DatabaseQueryController` class.

8. **pom.xml**:
   - Maven


Here is the complete code for the entire project structure:

### Project Structure

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
│   │   │               │   └── QueryRequest.java
│   │   │               ├── service/
│   │   │               │   └── DatabaseQueryService.java
│   │   │               └── DbQueryExecutorApplication.java
│   │   ├── resources/
│   │   │   ├── application.properties
│   │   │   └── logback-spring.xml (optional for logging configuration)
│   └── test/
│       └── java/
│           └── com/
│               └── example/
│                   └── dbqueryexecutor/
│                       ├── DatabaseQueryServiceTest.java
│                       └── DatabaseQueryControllerTest.java
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

### `application.properties`

```properties
spring.main.allow-bean-definition-overriding=true
```

### `DataSourceConfig.java`

```java
package com.example.dbqueryexecutor.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.jdbc.datasource.DriverManagerDataSource;

import javax.sql.DataSource;

@Configuration
public class DataSourceConfig {

    @Bean
    public DataSource dataSource() {
        return new DriverManagerDataSource();
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
    private DataSource dataSource;

    public void executeQueryAndWriteToExcel(
            String jdbcUrl, String jdbcUsername, String jdbcPassword,
            String query, String outputFilePath, List<String> extractionColumns, String separatorRegex) {

        DriverManagerDataSource driverManagerDataSource = (DriverManagerDataSource) dataSource;
        driverManagerDataSource.setUrl(jdbcUrl);
        driverManagerDataSource.setUsername(jdbcUsername);
        driverManagerDataSource.setPassword(jdbcPassword);

        try (Connection connection = driverManagerDataSource.getConnection();
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

### `QueryRequest.java`

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

### `DatabaseQueryController.java`

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


Here is the complete code for the Spring Boot project, adjusted for version 2.7.0, which includes fetching the database URL, username, and password through a JSON request:

### Project Structure

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
│   │   │               │   └── QueryRequest.java
│   │   │               ├── service/
│   │   │               │   └── DatabaseQueryService.java
│   │   │               └── DbQueryExecutorApplication.java
│   │   ├── resources/
│   │   │   └── application.properties
│   └── test/
│       └── java/
│           └── com/
│               └── example/
│                   └── dbqueryexecutor/
│                       ├── DatabaseQueryServiceTest.java
│                       └── DatabaseQueryControllerTest.java
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

### `application.properties`

```properties
spring.main.allow-bean-definition-overriding=true
```

### `DataSourceConfig.java`

```java
package com.example.dbqueryexecutor.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.jdbc.datasource.DriverManagerDataSource;

import javax.sql.DataSource;

@Configuration
public class DataSourceConfig {

    @Bean
    public DataSource dataSource() {
        return new DriverManagerDataSource();
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
    private DataSource dataSource;

    public void executeQueryAndWriteToExcel(
            String jdbcUrl, String jdbcUsername, String jdbcPassword,
            String query, String outputFilePath, List<String> extractionColumns, String separatorRegex) {

        DriverManagerDataSource driverManagerDataSource = (DriverManagerDataSource) dataSource;
        driverManagerDataSource.setUrl(jdbcUrl);
        driverManagerDataSource.setUsername(jdbcUsername);
        driverManagerDataSource.setPassword(jdbcPassword);

        try (Connection connection = driverManagerDataSource.getConnection();
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

### `QueryRequest.java`

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

### `DatabaseQueryController.java`

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
                queryRequest.getSeparator



### Description

Found object deserialization using `ObjectInputStream`. Deserializing entire Java objects is dangerous because malicious actors can create Java object streams with unintended consequences.

### Fix Recommendation

Ensure that the objects being deserialized are not user-controlled. If this must be done, consider the following security measures:

1. **Use HMACs to Sign the Data Stream**:
   - Implement integrity checks such as HMACs (Hash-based Message Authentication Codes) to ensure the data stream has not been tampered with.

2. **Transmit Only Object Fields**:
   - Instead of deserializing entire objects, transmit only necessary object fields and populate a new object with these fields.

### Example: Secure Deserialization with HMAC Verification

Below is an example demonstrating how to use HMACs to sign and verify the integrity of the serialized data stream before deserializing the object.

#### Example Language: Java

1. **HMAC Utility Class**:

```java
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.security.InvalidKeyException;
import java.security.NoSuchAlgorithmException;
import java.util.Arrays;

public class HmacUtil {
    private static final String HMAC_ALGO = "HmacSHA256";
    private static final byte[] SECRET_KEY = "your-secret-key".getBytes();

    public static byte[] calculateHMAC(byte[] data) throws NoSuchAlgorithmException, InvalidKeyException {
        Mac mac = Mac.getInstance(HMAC_ALGO);
        SecretKeySpec secretKeySpec = new SecretKeySpec(SECRET_KEY, HMAC_ALGO);
        mac.init(secretKeySpec);
        return mac.doFinal(data);
    }

    public static boolean verifyHMAC(byte[] data, byte[] hmac) throws NoSuchAlgorithmException, InvalidKeyException {
        byte[] calculatedHmac = calculateHMAC(data);
        return Arrays.equals(calculatedHmac, hmac);
    }
}
```

2. **ObjectCloner Class with HMAC Verification**:

```java
import java.io.*;

public class ObjectCloner {

    // Private constructor to prevent instantiation
    private ObjectCloner() { }

    // Returns a deep copy of an object with HMAC verification
    public static Object deepCopy(Object oldObj) throws Exception {
        ObjectOutputStream oos = null;
        ObjectInputStream ois = null;

        try {
            ByteArrayOutputStream bos = new ByteArrayOutputStream();
            oos = new ObjectOutputStream(bos);

            // Serialize and pass the object
            oos.writeObject(oldObj);
            oos.flush();

            // Calculate HMAC for the serialized data
            byte[] serializedData = bos.toByteArray();
            byte[] hmac = HmacUtil.calculateHMAC(serializedData);

            // Combine serialized data and HMAC
            ByteArrayOutputStream combinedBos = new ByteArrayOutputStream();
            combinedBos.write(serializedData);
            combinedBos.write(hmac);
            byte[] combinedData = combinedBos.toByteArray();

            // Deserialize the object with HMAC verification
            ByteArrayInputStream bin = new ByteArrayInputStream(combinedData, 0, combinedData.length - hmac.length);
            byte[] receivedHmac = Arrays.copyOfRange(combinedData, combinedData.length - hmac.length, combinedData.length);

            if (!HmacUtil.verifyHMAC(bin.readAllBytes(), receivedHmac)) {
                throw new SecurityException("Data integrity check failed. The data may have been tampered with.");
            }

            bin = new ByteArrayInputStream(combinedData, 0, combinedData.length - hmac.length);
            ois = new ObjectInputStream(bin);

            // Return the new object
            return ois.readObject();
        } catch (Exception e) {
            System.out.println("Exception in ObjectCloner: " + e);
            throw e;
        } finally {
            if (oos != null) {
                oos.close();
            }
            if (ois != null) {
                ois.close();
            }
        }
    }
}
```

### Summary

- **Integrity Checks**: Use HMACs to sign and verify serialized data to ensure it hasn't been tampered with.
- **Deserialization Security**: Verify the integrity of the data before deserializing to protect against malicious object streams.
- **Transmit Only Fields**: When possible, transmit only the necessary fields and populate new objects instead of deserializing entire objects.
- 

Generating and securely managing a secret key is crucial for ensuring the integrity and confidentiality of your data. Here are some methods to generate and manage a secret key in Java:

### Generating a Secret Key

You can use Java's `KeyGenerator` class to generate a secret key for HMAC or other cryptographic operations. Here is an example of how to generate and use a secret key:

#### Example: Generating a Secret Key

```java
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import java.security.NoSuchAlgorithmException;
import java.util.Base64;

public class SecretKeyUtil {

    // Generate a new secret key
    public static SecretKey generateSecretKey() throws NoSuchAlgorithmException {
        KeyGenerator keyGen = KeyGenerator.getInstance("HmacSHA256");
        keyGen.init(256); // Set the key size
        return keyGen.generateKey();
    }

    // Convert secret key to a string
    public static String encodeKey(SecretKey secretKey) {
        return Base64.getEncoder().encodeToString(secretKey.getEncoded());
    }

    // Convert a string back to a secret key
    public static SecretKey decodeKey(String encodedKey) {
        byte[] decodedKey = Base64.getDecoder().decode(encodedKey);
        return new SecretKeySpec(decodedKey, 0, decodedKey.length, "HmacSHA256");
    }

    public static void main(String[] args) throws NoSuchAlgorithmException {
        // Generate a new secret key
        SecretKey secretKey = generateSecretKey();
        String encodedKey = encodeKey(secretKey);

        // Print the encoded key
        System.out.println("Encoded Secret Key: " + encodedKey);

        // Decode the key
        SecretKey decodedKey = decodeKey(encodedKey);
    }
}
```

### Using the Secret Key in HMAC

You can modify the HMAC utility class to use the generated secret key:

```java
import javax.crypto.Mac;
import javax.crypto.SecretKey;
import javax.crypto.spec.SecretKeySpec;
import java.security.InvalidKeyException;
import java.security.NoSuchAlgorithmException;
import java.util.Arrays;

public class HmacUtil {
    private static final String HMAC_ALGO = "HmacSHA256";

    public static byte[] calculateHMAC(byte[] data, SecretKey secretKey) throws NoSuchAlgorithmException, InvalidKeyException {
        Mac mac = Mac.getInstance(HMAC_ALGO);
        mac.init(secretKey);
        return mac.doFinal(data);
    }

    public static boolean verifyHMAC(byte[] data, byte[] hmac, SecretKey secretKey) throws NoSuchAlgorithmException, InvalidKeyException {
        byte[] calculatedHmac = calculateHMAC(data, secretKey);
        return Arrays.equals(calculatedHmac, hmac);
    }
}
```

### Secure Storage of Secret Keys

To securely store and manage secret keys, consider the following approaches:

1. **Environment Variables**: Store the secret key in an environment variable and retrieve it at runtime.
2. **Configuration Files**: Store the key in a secured configuration file with proper access controls.
3. **Secrets Management Services**: Use a secrets management service such as AWS Secrets Manager, Azure Key Vault, or HashiCorp Vault.

#### Example: Using an Environment Variable

```java
public class SecretKeyFromEnv {

    public static SecretKey getSecretKeyFromEnv() {
        String encodedKey = System.getenv("HMAC_SECRET_KEY");
        if (encodedKey == null) {
            throw new IllegalStateException("Environment variable HMAC_SECRET_KEY not set");
        }
        byte[] decodedKey = Base64.getDecoder().decode(encodedKey);
        return new SecretKeySpec(decodedKey, 0, decodedKey.length, "HmacSHA256");
    }
}
```

### Summary

1. **Generate a Secret Key**: Use `KeyGenerator` to generate a new secret key.
2. **Encode and Decode**: Convert the key to a string for storage and decode it when needed.
3. **Use the Key in HMAC**: Use the secret key for calculating and verifying HMAC.
4. **Secure Storage**: Store the secret key securely using environment variables, configuration files, or secrets management services.

Ensure that your secret key management practices comply with your organization's security policies and industry best practices.

Certainly! Let's modify the code to write the serialized data with HMAC to a text file and read it back from the file for deserialization.

### Serialization with HMAC Generation and Writing to File

1. **SerializationUtil**: Modify to write the serialized data with HMAC to a file.

```java
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.io.*;
import java.security.Key;

public class SerializationUtil {

    private static final String HMAC_ALGO = "HmacSHA256";
    private static final String SECRET_KEY = "secret_key"; // Use a strong key in real applications

    public static void serializeWithHMAC(Object obj, String filePath) throws Exception {
        ByteArrayOutputStream byteOutStream = new ByteArrayOutputStream();
        BufferedOutputStream bufferedOutStream = new BufferedOutputStream(byteOutStream);
        ObjectOutputStream objectOutStream = new ObjectOutputStream(bufferedOutStream);

        objectOutStream.writeObject(obj);
        objectOutStream.flush();
        bufferedOutStream.flush();

        byte[] serializedData = byteOutStream.toByteArray();
        byte[] hmac = generateHMAC(serializedData);

        ByteArrayOutputStream combinedStream = new ByteArrayOutputStream();
        BufferedOutputStream combinedBufferedOutStream = new BufferedOutputStream(combinedStream);

        combinedBufferedOutStream.write(serializedData);
        combinedBufferedOutStream.write(hmac);
        combinedBufferedOutStream.flush();

        byte[] finalData = combinedStream.toByteArray();

        try (FileOutputStream fileOutStream = new FileOutputStream(filePath);
             BufferedOutputStream fileBufferedOutStream = new BufferedOutputStream(fileOutStream)) {
            fileBufferedOutStream.write(finalData);
            fileBufferedOutStream.flush();
        }
    }

    private static byte[] generateHMAC(byte[] data) throws Exception {
        Key hmacKey = new SecretKeySpec(SECRET_KEY.getBytes(), HMAC_ALGO);
        Mac mac = Mac.getInstance(HMAC_ALGO);
        mac.init(hmacKey);
        return mac.doFinal(data);
    }
}
```

### Deserialization with HMAC Verification and Reading from File

2. **DeserializationUtil**: Modify to read the serialized data with HMAC from a file.

```java
import java.io.*;
import java.util.Arrays;

public class DeserializationUtil {

    public static Object deserializeWithHMAC(String filePath) throws Exception {
        byte[] data;

        try (FileInputStream fileInStream = new FileInputStream(filePath);
             BufferedInputStream fileBufferedInStream = new BufferedInputStream(fileInStream)) {
            data = fileBufferedInStream.readAllBytes();
        }

        int hmacLength = 32; // Length of HMAC-SHA256
        byte[] serializedData = Arrays.copyOfRange(data, 0, data.length - hmacLength);
        byte[] receivedHMAC = Arrays.copyOfRange(data, data.length - hmacLength, data.length);

        byte[] computedHMAC = SerializationUtil.generateHMAC(serializedData);

        if (!Arrays.equals(receivedHMAC, computedHMAC)) {
            throw new SecurityException("Data integrity check failed.");
        }

        ByteArrayInputStream byteInStream = new ByteArrayInputStream(serializedData);
        BufferedInputStream bufferedInStream = new BufferedInputStream(byteInStream);
        ObjectInputStream objectInStream = new ObjectInputStream(bufferedInStream);

        return objectInStream.readObject();
    }
}
```

### Main Class to Test Serialization and Deserialization

3. **Main Class**: Modify to test writing to and reading from a text file.

```java
public class Main {
    public static void main(String[] args) {
        String filePath = "serialized_data.txt";

        try {
            MyClass obj = new MyClass("Hello, World!");
            SerializationUtil.serializeWithHMAC(obj, filePath);

            MyClass deserializedObj = (MyClass) DeserializationUtil.deserializeWithHMAC(filePath);
            System.out.println(deserializedObj.getMessage());
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
```

4. **Definition of `MyClass`**:

```java
import java.io.Serializable;

public class MyClass implements Serializable {
    private static final long serialVersionUID = 1L;
    private String message;

    public MyClass(String message) {
        this.message = message;
    }

    public String getMessage() {
        return message;
    }

    public void setMessage(String message) {
        this.message = message;
    }
}
```

### Notes

- **File Paths**: Ensure the file path used in `filePath` is correct and accessible for writing and reading.
- **Buffer Size**: Buffered streams are used to enhance performance, especially for larger data sizes.
- **Security**: Proper key management and security practices should be implemented in a production environment.

To modify the code so that it can insert data into the given columns of an Excel sheet through a REST client, we need to:

1. Create an endpoint to accept data through a REST client.
2. Write the data into the specified columns of the Excel sheet.
3. Validate the data as specified.

Here's how you can achieve this:

### Dependencies
Ensure the following dependencies are included in your `pom.xml`:
```xml
<dependencies>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter</artifactId>
    </dependency>
    <dependency>
        <groupId>org.apache.poi</groupId>
        <artifactId>poi</artifactId>
        <version>5.2.3</version>
    </dependency>
    <dependency>
        <groupId>org.apache.poi</groupId>
        <artifactId>poi-ooxml</artifactId>
        <version>5.2.3</version>
    </dependency>
</dependencies>
```

### Main Application
Create the main application class:
```java
package com.example.excelprocessor;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class ExcelProcessorApplication {

    public static void main(String[] args) {
        SpringApplication.run(ExcelProcessorApplication.class, args);
    }
}
```

### DTO Class
Create a DTO class to hold the data coming from the REST client:
```java
package com.example.excelprocessor.dto;

public class DataDTO {
    private String column1;
    private String column2;
    private String effectiveDate;

    // Getters and Setters
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

    public String getEffectiveDate() {
        return effectiveDate;
    }

    public void setEffectiveDate(String effectiveDate) {
        this.effectiveDate = effectiveDate;
    }
}
```

### Service Class
Create a service class to handle the Excel file processing:
```java
package com.example.excelprocessor.service;

import com.example.excelprocessor.dto.DataDTO;
import org.apache.poi.ss.usermodel.*;
import org.apache.poi.xssf.usermodel.XSSFWorkbook;
import org.springframework.stereotype.Service;

import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;

@Service
public class ExcelProcessorService {

    public void insertDataToExcel(String filePath, DataDTO data) throws IOException {
        FileInputStream excelFile = new FileInputStream(filePath);
        Workbook workbook = new XSSFWorkbook(excelFile);
        Sheet sheet = workbook.getSheetAt(0);

        Row newRow = sheet.createRow(sheet.getLastRowNum() + 1);

        insertCellData(newRow, 0, data.getColumn1());
        insertCellData(newRow, 1, data.getColumn2());
        insertCellData(newRow, 2, data.getEffectiveDate());

        FileOutputStream outputStream = new FileOutputStream(filePath);
        workbook.write(outputStream);
        workbook.close();
        outputStream.close();
    }

    private void insertCellData(Row row, int cellIndex, String value) {
        if (value == null || value.trim().isEmpty() || value.contains("'")) {
            throw new IllegalArgumentException("Invalid cell value: " + value);
        }
        Cell cell = row.createCell(cellIndex);
        cell.setCellValue(value);
    }
}
```

### Controller Class
Create a controller class to expose the endpoint:
```java
package com.example.excelprocessor.controller;

import com.example.excelprocessor.dto.DataDTO;
import com.example.excelprocessor.service.ExcelProcessorService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import java.io.IOException;

@RestController
@RequestMapping("/excel")
public class ExcelProcessorController {

    @Autowired
    private ExcelProcessorService excelProcessorService;

    @PostMapping("/insertData")
    public String insertDataToExcel(@RequestParam String filePath, @RequestBody DataDTO data) {
        try {
            excelProcessorService.insertDataToExcel(filePath, data);
            return "Data inserted successfully.";
        } catch (IOException e) {
            return "Error processing Excel file: " + e.getMessage();
        } catch (IllegalArgumentException e) {
            return "Validation error: " + e.getMessage();
        }
    }
}
```

### Running the Application
Run the application and use a REST client to insert data into the Excel sheet:
```
POST http://localhost:8080/excel/insertData?filePath=/path/to/your/excel/file.xlsx
Content-Type: application/json

{
    "column1": "value1",
    "column2": "value2",
    "effectiveDate": "2024-01-01"
}
```

This setup provides an endpoint to insert data into an Excel sheet, validates the data to ensure no single quotes or empty cells, and ensures the "Effective Date" is a text value. Ensure the column indices and validation logic match your actual Excel file structure and requirements.


The provided code attempts to create a deep copy of an object using serialization and deserialization. However, it has several issues, including syntax errors, improper exception handling, and lack of security considerations for deserialization. Here is a corrected and improved version of the code:

```java
import java.io.*;

public class ObjectCloner {

    // Private constructor to prevent instantiation
    private ObjectCloner() { }

    // Returns a deep copy of an object
    public static Object deepCopy(Object oldObj) throws Exception {
        ObjectOutputStream oos = null;
        ObjectInputStream ois = null;
        
        try {
            ByteArrayOutputStream bos = new ByteArrayOutputStream();
            oos = new ObjectOutputStream(bos);
            
            // Serialize and pass the object
            oos.writeObject(oldObj);
            oos.flush();

            ByteArrayInputStream bin = new ByteArrayInputStream(bos.toByteArray());
            ois = new ObjectInputStream(bin);

            // Return the new object
            return ois.readObject();
        } catch (Exception e) {
            System.out.println("Exception in ObjectCloner: " + e);
            throw e;
        } finally {
            if (oos != null) {
                oos.close();
            }
            if (ois != null) {
                ois.close();
            }
        }
    }
}
```

### Key Improvements:

1. **Syntax Corrections**: Fixed syntax errors such as missing semicolons and improper object creation.
2. **Exception Handling**: Improved exception handling to ensure proper closing of streams.
3. **Security Considerations**: This code still lacks security measures for deserialization. To enhance security, consider implementing class whitelisting during deserialization as shown in the earlier examples.

### Secure Deserialization Example:

To make the deserialization process secure, you can use a custom `ObjectInputStream` class to restrict which classes are allowed to be deserialized:

```java
public class SecureObjectInputStream extends ObjectInputStream {

    public SecureObjectInputStream(InputStream in) throws IOException {
        super(in);
    }

    @Override
    protected Class<?> resolveClass(ObjectStreamClass desc) throws IOException, ClassNotFoundException {
        if (!desc.getName().equals("your.package.YourClass")) {
            throw new InvalidClassException("Unauthorized deserialization attempt", desc.getName());
        }
        return super.resolveClass(desc);
    }
}

// Updated deepCopy method to use SecureObjectInputStream
public static Object deepCopy(Object oldObj) throws Exception {
    ObjectOutputStream oos = null;
    ObjectInputStream ois = null;

    try {
        ByteArrayOutputStream bos = new ByteArrayOutputStream();
        oos = new ObjectOutputStream(bos);

        // Serialize and pass the object
        oos.writeObject(oldObj);
        oos.flush();

        ByteArrayInputStream bin = new ByteArrayInputStream(bos.toByteArray());
        ois = new SecureObjectInputStream(bin);

        // Return the new object
        return ois.readObject();
    } catch (Exception e) {
        System.out.println("Exception in ObjectCloner: " + e);
        throw e;
    } finally {
        if (oos != null) {
            oos.close();
        }
        if (ois != null) {
            ois.close();
        }
    }
}
```

This ensures that only specific classes are allowed to be deserialized, thereby mitigating the risk of deserialization attacks. Adjust the class name in the `resolveClass` method as per your application's requirements.


import java.io.*;

public class ObjectCloner {

    private ObjectCloner() { }

    public static Object deepCopy(Object oldObj) throws Exception {
        ObjectOutputStream oos = null;
        LookAheadObjectInputStream ois = null;
        try {
            ByteArrayOutputStream bos = new ByteArrayOutputStream();
            oos = new ObjectOutputStream(bos);
            oos.writeObject(oldObj);
            oos.flush();

            ByteArrayInputStream bin = new ByteArrayInputStream(bos.toByteArray());
            ois = new LookAheadObjectInputStream(bin);
            return ois.readObject();
        } catch (Exception e) {
            System.out.println("Exception in ObjectCloner = " + e);
            throw e;
        } finally {
            if (oos != null) {
                oos.close();
            }
            if (ois != null) {
                ois.close();
            }
        }
    }
}

class LookAheadObjectInputStream extends ObjectInputStream {
    public LookAheadObjectInputStream(InputStream inputStream) throws IOException {
        super(inputStream);
    }

    @Override
    protected Class<?> resolveClass(ObjectStreamClass desc) throws IOException, ClassNotFoundException {
        // Replace with your expected class name
        if (!desc.getName().equals("com.example.Bicycle")) {
            throw new InvalidClassException("Unauthorized deserialization attempt", desc.getName());
        }
        return super.resolveClass(desc);
    }
}


To secure deserialization in Java, you should implement measures to prevent unauthorized or malicious data from being deserialized. Here are some strategies, examples, and best practices to follow:

### Avoid Accepting Serialized Objects from Untrusted Sources
The safest approach is not to accept serialized objects from untrusted sources. This eliminates the risk of deserialization attacks entirely.

### Integrity Checks
Implement integrity checks such as digital signatures to ensure the data has not been tampered with.

### Enforce Type Constraints
Override the `ObjectInputStream` class to enforce strict type constraints.

### Example: Rejecting Deserialization
Preventing deserialization by overriding the `readObject` method:

```java
import java.io.IOException;
import java.io.ObjectInputStream;

public class SecureClass implements Serializable {
    // Other class details

    private final void readObject(ObjectInputStream in) throws IOException {
        throw new IOException("Deserialization is not allowed");
    }
}
```

### Example: Restricting Allowed Types
Using a custom `ObjectInputStream` to restrict deserialization to specific classes:

```java
import java.io.IOException;
import java.io.InputStream;
import java.io.InvalidClassException;
import java.io.ObjectInputStream;
import java.io.ObjectStreamClass;

public class LookAheadObjectInputStream extends ObjectInputStream {
    public LookAheadObjectInputStream(InputStream inputStream) throws IOException {
        super(inputStream);
    }

    @Override
    protected Class<?> resolveClass(ObjectStreamClass desc) throws IOException, ClassNotFoundException {
        if (!desc.getName().equals("com.example.Bicycle")) {
            throw new InvalidClassException("Unauthorized deserialization attempt", desc.getName());
        }
        return super.resolveClass(desc);
    }
}
```

### Additional Recommendations
- **Isolate Deserialization**: Run deserialization code in a low-privilege environment.
- **Log Deserialization Activities**: Log and monitor deserialization activities and exceptions.
- **Network Restrictions**: Restrict or monitor network connectivity for systems that perform deserialization.
- **Exception Handling**: Ensure proper handling and logging of deserialization exceptions.

### Applying These Principles
When implementing deep copying or any serialization/deserialization logic, incorporate these best practices. Here’s an example of using the `LookAheadObjectInputStream` in your `ObjectCloner` class:

```java
import java.io.*;

public class ObjectCloner {

    private ObjectCloner() { }

    public static Object deepCopy(Object oldObj) throws Exception {
        ObjectOutputStream oos = null;
        LookAheadObjectInputStream ois = null;
        try {
            ByteArrayOutputStream bos = new ByteArrayOutputStream();
            oos = new ObjectOutputStream(bos);
            oos.writeObject(oldObj);
            oos.flush();

            ByteArrayInputStream bin = new ByteArrayInputStream(bos.toByteArray());
            ois = new LookAheadObjectInputStream(bin);
            return ois.readObject();
        } catch (Exception e) {
            System.out.println("Exception in ObjectCloner = " + e);
            throw e;
        } finally {
            if (oos != null) {
                oos.close();
            }
            if (ois != null) {
                ois.close();
            }
        }
    }
}

class LookAheadObjectInputStream extends ObjectInputStream {
    public LookAheadObjectInputStream(InputStream inputStream) throws IOException {
        super(inputStream);
    }

    @Override
    protected Class<?> resolveClass(ObjectStreamClass desc) throws IOException, ClassNotFoundException {
        // Replace with your expected class name
        if (!desc.getName().equals("com.example.Bicycle")) {
            throw new InvalidClassException("Unauthorized deserialization attempt", desc.getName());
        }
        return super.resolveClass(desc);
    }
}
```

### Conclusion
Securing deserialization in Java involves rejecting unauthorized deserialization attempts, enforcing type constraints, and isolating deserialization processes. By following these recommendations, you can mitigate the risks associated with deserialization vulnerabilities.


import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.stream.Stream;

public class FileSearch {

    public static void main(String[] args) {
        // Provide the directory path to search in
        String directoryPath = "/path/to/your/project";
        // The word to search for
        String wordToFind = "yourSearchWord";

        // Search the directory
        searchFiles(new File(directoryPath), wordToFind);
    }

    private static void searchFiles(File directory, String wordToFind) {
        // Get all files and directories in the current directory
        File[] files = directory.listFiles();

        if (files != null) {
            for (File file : files) {
                if (file.isDirectory()) {
                    // If the file is a directory, recursively search within it
                    searchFiles(file, wordToFind);
                } else if (file.isFile()) {
                    // If the file is a regular file, check if it contains the word
                    if (containsWord(file, wordToFind)) {
                        System.out.println("Word found in file: " + file.getAbsolutePath());
                    }
                }
            }
        }
    }

    private static boolean containsWord(File file, String wordToFind) {
        try (Stream<String> lines = Files.lines(Paths.get(file.getAbsolutePath()))) {
            // Check if any line in the file contains the word
            return lines.anyMatch(line -> line.contains(wordToFind));
        } catch (IOException e) {
            e.printStackTrace();
        }
        return false;
    }
}


import java.io.File;
import java.io.IOException;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.nio.file.StandardOpenOption;
import java.util.Scanner;
import java.util.stream.Stream;

public class FileSearch {

    public static void main(String[] args) {
        // Provide the directory path to search in
        String directoryPath = "/path/to/your/project";

        // Scanner for user input
        Scanner scanner = new Scanner(System.in);
        
        while (true) {
            // Prompt user for input
            System.out.print("Enter the word to search for (or '1011' to exit): ");
            String wordToFind = scanner.nextLine();

            // Check if the user wants to exit
            if ("1011".equals(wordToFind)) {
                System.out.println("Exiting the program...");
                break;
            }

            // Search the directory for the word
            searchFiles(new File(directoryPath), wordToFind);
        }

        scanner.close();
    }

    private static void searchFiles(File directory, String wordToFind) {
        // Get all files and directories in the current directory
        File[] files = directory.listFiles();

        if (files != null) {
            for (File file : files) {
                if (file.isDirectory()) {
                    // If the file is a directory, recursively search within it
                    searchFiles(file, wordToFind);
                } else if (file.isFile()) {
                    // If the file is a regular file, check if it contains the word
                    if (containsWord(file, wordToFind)) {
                        System.out.println("Word found in file: " + file.getAbsolutePath());
                    }
                }
            }
        }
    }

    private static boolean containsWord(File file, String wordToFind) {
        Charset charset = StandardCharsets.UTF_8; // Or use StandardCharsets.ISO_8859_1 for a more lenient charset

        try (Stream<String> lines = Files.lines(Paths.get(file.getAbsolutePath()), charset)) {
            // Check if any line in the file contains the word
            return lines.anyMatch(line -> line.contains(wordToFind));
        } catch (IOException e) {
            // Handle the error, possibly skipping the file that causes issues
            System.err.println("Could not read file: " + file.getAbsolutePath() + " - " + e.getMessage());
        }
        return false;
    }
}
=MID(A1,FIND("/",A1,FIND("/",A1)+1)+1,FIND("/",A1,FIND("/",A1,FIND("/",A1)+1)+1)-FIND("/",A1,FIND("/",A1)+1)-1)


export CATALINA_OPTS="$CATALINA_OPTS -agentlib:jdwp=transport=dt_socket,address=8000,server=y,suspend=n"


public void downLoad(ReportCalculationContext reportContext) throws Exception {
    URL url = getUrl();
    if (url == null) {
        throw new Exception("URL cannot be null");
    }
    log.info("Started downloading from URL: " + url);

    String downLoadToDir = getDownLoadToDir();
    String host = reportContext.getParameter(Constants.PROXY_HOST).getValue().getStringValue();
    int port = Integer.parseInt(reportContext.getParameter(Constants.PROXY_PORT).getValue().getStringValue());
    log.info("Using proxy: " + host + ":" + port);

    Proxy proxy = new Proxy(Proxy.Type.HTTP, new InetSocketAddress(host, port));
    SSLContext sslContext = SSLContext.getInstance("TLS");
    sslContext.init(null, new TrustManager[]{new X509TrustManager() {
        @Override
        public void checkClientTrusted(X509Certificate[] x509Certificates, String s) { }
        @Override
        public void checkServerTrusted(X509Certificate[] x509Certificates, String s) { }
        @Override
        public X509Certificate[] getAcceptedIssuers() {
            return new X509Certificate[0];
        }
    }}, new SecureRandom());

    HttpsURLConnection conn = (HttpsURLConnection) url.openConnection(proxy);
    conn.setSSLSocketFactory(sslContext.getSocketFactory());
    conn.setConnectTimeout(connectionTimeout);
    conn.setReadTimeout(readTimeout);

    // Add headers
    conn.addRequestProperty("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36");
    conn.addRequestProperty("Referer", "https://example.com");
    conn.addRequestProperty("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8");
    conn.addRequestProperty("Accept-Language", "en-US,en;q=0.5");

    // Check the response code
    int responseCode = conn.getResponseCode();
    if (responseCode == 403) {
        log.error("Server returned 403 Forbidden for URL: " + url);
        throw new IOException("Server returned 403 Forbidden for URL: " + url);
    } else if (responseCode >= 400) {
        log.error("Server returned error code: " + responseCode + " for URL: " + url);
        throw new IOException("Server returned error code: " + responseCode);
    }

    // Download the file
    try (InputStream in = conn.getInputStream();
         OutputStream out = getFileOutputStream(downLoadToDir, new File(url.getPath()).getName())) {
        byte[] buffer = new byte[8192];
        int bytesRead;
        while ((bytesRead = in.read(buffer)) != -1) {
            out.write(buffer, 0, bytesRead);
        }
        log.info("Download Complete: " + downLoadToDir);
    } catch (IOException e) {
        log.error("Error during file download", e);
        throw e;
    }
}
