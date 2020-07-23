package example;

import com.opencsv.CSVWriter;
import java.io.StringWriter;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Timestamp;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.Arrays;
import java.util.Map;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DataAccessException;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Component;

@Component
public class Extractor {

  @Autowired
  private NamedParameterJdbcTemplate jdbcTemplate;

  public String extract(Long requestParam1, Long requestParam2) {
    MapSqlParameterSource paramSource = getMapSqlParameterSource(requestParam1, requestParam2);
    //language=SQL
    final String query = "A_QUERY";

    // new values need to be added to the end of the list
    String[] columns = {"SOME_COLUMNS"};

    return extractToCSV("extracted-stuff", query, paramSource, columns);
  }

  private String extractToCSV(String fileName, String query, MapSqlParameterSource paramSource, String[] columns,
                              Map<String) {
    StringWriter writer = new StringWriter();
    CSVWriter csvWriter = new CSVWriter(writer, ',', '"', '\\', "\n");
    // write header
    csvWriter.writeNext(columns);

    try {
      jdbcTemplate.query(query, paramSource,
          (rs, rowNum) -> {
            String[] row = extractRow(columns, rs);
            csvWriter.writeNext(row, true);
            return null;
          }
      );
    } catch (DataAccessException e) {
      csvWriter.writeNext(new String[] {"FAILED", e.getMessage()});
    }

    return Util.writeFileToS3(fileName + System.currentTimeMillis() + ".csv", writer.getBuffer().toString());
  }


  private String[] extractRow(String[] columns, ResultSet rs) {
    return Arrays.stream(columns).map(col -> {
      try {
        final Object object = rs.getObject(col);

        if (object != null) {
          return object.toString();
        }

        return "";
      } catch (SQLException e) {
        return "ERROR: " + e.getMessage();
      }
    }).toArray(String[]::new);
  }

  private MapSqlParameterSource getMapSqlParameterSource(Long requestParam1, Long requestParam2) {
    MapSqlParameterSource paramSource = new MapSqlParameterSource();
    if (requestParam2 != null) {
      // get the epoch in local time
      paramSource.addValue("requestParam1", createTimestamp(requestParam1));
    }
    if (requestParam1 != null) {
      paramSource.addValue("requestParam2", createTimestamp(requestParam2));
    }
    return paramSource;
  }

  private Timestamp createTimestamp(Long epochMs) {
    LocalDateTime dateTime = LocalDateTime.ofInstant(Instant.ofEpochMilli(epochMs), ZoneId.of("UTC"));
    return Timestamp.valueOf(dateTime);
  }
}
