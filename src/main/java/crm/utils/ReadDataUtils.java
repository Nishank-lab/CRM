package crm.utils;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.web.multipart.MultipartFile;

import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;

/**
 * Cloud-native file reading utility
 * Replaced desktop JFileChooser with web-based multipart file handling
 */
public class ReadDataUtils {

    private static final Logger log = LoggerFactory.getLogger(ReadDataUtils.class);

    /**
     * @deprecated This method uses JFileChooser which is incompatible with cloud environments.
     * Use {@link #processUploadedFile(MultipartFile)} instead for web-based file uploads.
     */
    @Deprecated
    public static File ReadFile(String dialogMessage, Object parent, String fileExtensionDescription,
                                String... fileExtension) {
        log.warn("DEPRECATED: JFileChooser-based file reading is not supported in cloud environments. " +
                "Use web-based file upload (MultipartFile) instead.");
        throw new UnsupportedOperationException(
                "JFileChooser is not supported in cloud/server environments. " +
                "Please use web-based file upload endpoints with MultipartFile."
        );
    }

    /**
     * Cloud-native file processing from web upload
     * @param file MultipartFile from web upload
     * @return InputStream for processing the uploaded file
     * @throws IOException if file cannot be read
     */
    public static InputStream processUploadedFile(MultipartFile file) throws IOException {
        if (file == null || file.isEmpty()) {
            throw new IllegalArgumentException("File cannot be null or empty");
        }

        log.info("Processing uploaded file: {} (size: {} bytes)", file.getOriginalFilename(), file.getSize());
        return file.getInputStream();
    }

    /**
     * Cloud-native temporary file creation for uploaded files
     * @param file MultipartFile from web upload
     * @param prefix Prefix for temp file
     * @return Path to temporary file
     * @throws IOException if file cannot be written
     */
    public static Path saveUploadedFileTemporarily(MultipartFile file, String prefix) throws IOException {
        if (file == null || file.isEmpty()) {
            throw new IllegalArgumentException("File cannot be null or empty");
        }

        String originalFilename = file.getOriginalFilename();
        String suffix = originalFilename != null && originalFilename.contains(".")
                ? originalFilename.substring(originalFilename.lastIndexOf("."))
                : ".tmp";

        Path tempFile = Files.createTempFile(prefix, suffix);
        try (InputStream inputStream = file.getInputStream()) {
            Files.copy(inputStream, tempFile, StandardCopyOption.REPLACE_EXISTING);
            log.info("Saved uploaded file to temporary location: {}", tempFile);
            return tempFile;
        }
    }

    /**
     * Validate file extension for uploaded files
     * @param filename Original filename
     * @param allowedExtensions Allowed file extensions
     * @return true if extension is allowed
     */
    public static boolean isValidFileExtension(String filename, String... allowedExtensions) {
        if (filename == null || filename.isEmpty()) {
            return false;
        }

        String extension = "";
        int lastDot = filename.lastIndexOf('.');
        if (lastDot > 0) {
            extension = filename.substring(lastDot + 1).toLowerCase();
        }

        for (String allowed : allowedExtensions) {
            if (extension.equals(allowed.toLowerCase())) {
                return true;
            }
        }

        log.warn("Invalid file extension: {}. Allowed: {}", extension, String.join(", ", allowedExtensions));
        return false;
    }

}
