# Test
To convert the provided code to a Spring Boot application, we'll create a structured project that utilizes Spring Boot's capabilities for managing the database connection, reading files, and handling user input. Here's how the code can be adapted:

### Project Structure
1. **`src/main/java/com/example/dbqueryexecutor/DatabaseQueryExecutorApplication.java`**: The main class to run the Spring Boot application.
2. **`src/main/java/com/example/dbqueryexecutor/controller/QueryController.java`**: REST controller to handle HTTP requests.
3. **`src/main/java/com/example/dbqueryexecutor/service/DatabaseQueryService.java`**: Service to encapsulate the database query and Excel writing logic.
4. **`src/main/java/com/example/dbqueryexecutor/model/QueryRequest.java`**: Model to handle the request payload.
5. **`src/main/resources/application.properties`**: Configuration file for database connection and other properties.

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

spring.jpa.show-sql=true
spring.jpa.hibernate.ddl-auto=none
```

### Running the Application
1. Create a new Spring Boot project using your preferred method (e.g., Spring Initializr).
2. Add dependencies for Spring Web, Spring Data JPA, and the Apache POI library to your `pom.xml`.
3. Update the `application.properties` file with your database connection details.
4. Create the files as shown above in the appropriate package structure.
5. Start the Spring Boot application and use a tool like Postman to send a POST request to `http://localhost:8080/api/query/execute` with the necessary files and JSON payload.

This Spring Boot application will now read the database credentials from the `application.properties` file, handle HTTP requests to execute SQL queries, extract key-value pairs, and write the results to an Excel file.
