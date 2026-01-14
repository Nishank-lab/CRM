package crm.csv;

import com.opencsv.CSVReader;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.FileReader;
import java.io.IOException;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.List;

/**
 * Cloud-native CSV Test utility
 * Updated to use structured logging instead of System.out.println
 * Removed JFileChooser dependency (incompatible with cloud environments)
 */
public class CSVTest {

    private static final Logger log = LoggerFactory.getLogger(CSVTest.class);

    public static void main(String[] args) {
        if (args.length == 0) {
            log.error("No CSV file path provided. Usage: java CSVTest <csv-file-path>");
            System.exit(1);
        }

        String csvFilePath = args[0];
        log.info("Processing CSV file: {}", csvFilePath);

        Path csvPath = Paths.get(csvFilePath);
        if (!csvPath.toFile().exists()) {
            log.error("CSV file not found: {}", csvFilePath);
            System.exit(1);
        }

        CSVReader reader = null;
        List<Object[]> data = new ArrayList<>();
        try {
            reader = new CSVReader(new FileReader(csvPath.toFile()));
            String[] line;
            int lineNumber = 0;

            while ((line = reader.readNext()) != null) {
                lineNumber++;
                data.add(line);

                if (line.length > 1 && "QUICK SUB".equals(line[1])) {
                    String logLine = String.format("Line %d: %s | %s | %s",
                            lineNumber,
                            line.length > 0 ? line[0] : "",
                            line.length > 1 ? line[1] : "",
                            line.length > 2 ? line[2] : "");
                    log.info("Found matching record: {}", logLine);
                }
            }

            log.info("CSV processing completed. Total lines processed: {}", lineNumber);

        } catch (IOException e) {
            log.error("Error reading CSV file: {}", csvFilePath, e);
            System.exit(1);
        } finally {
            if (reader != null) {
                try {
                    reader.close();
                } catch (IOException e) {
                    log.warn("Error closing CSV reader", e);
                }
            }
        }
    }

}
