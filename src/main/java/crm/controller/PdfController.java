package crm.controller;

import com.itextpdf.text.Document;
import com.itextpdf.text.DocumentException;
import com.itextpdf.text.Paragraph;
import com.itextpdf.text.pdf.PdfWriter;
import crm.entity.Pdf;
import crm.service.PdfService;
import lombok.extern.slf4j.Slf4j;
import org.slf4j.MDC;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.validation.BindingResult;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;

import javax.validation.Valid;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.util.UUID;

@Controller
@Slf4j
public class PdfController {

    private PdfService pdfService;

    @Value("${aws.s3.bucket.name:crm-pdf-bucket}")
    private String s3BucketName;

    @Value("${pdf.storage.enabled:false}")
    private boolean storageEnabled;

    public PdfController(PdfService pdfService) {
        this.pdfService = pdfService;
    }

    private byte[] generateSamplePdf(String fileName, String text) throws DocumentException, IOException {
        String correlationId = MDC.get("correlationId");
        if (correlationId == null) {
            correlationId = UUID.randomUUID().toString();
            MDC.put("correlationId", correlationId);
        }

        if (!fileName.endsWith(".pdf")) {
            fileName += ".pdf";
        }

        log.info("Generating PDF: {} with correlationId: {}", fileName, correlationId);

        ByteArrayOutputStream outputStream = new ByteArrayOutputStream();
        Document document = new Document();
        try {
            PdfWriter.getInstance(document, outputStream);
            document.open();
            Paragraph paragraph = new Paragraph(text);
            document.add(paragraph);
            document.close();

            log.info("PDF generated successfully: {} (size: {} bytes)", fileName, outputStream.size());

            // Cloud-native: Store in S3 or return bytes for further processing
            // This approach avoids local file system writes
            return outputStream.toByteArray();
        } finally {
            if (document.isOpen()) {
                document.close();
            }
        }
    }

    @GetMapping("/pdf-generator")
    public String pdfGenerator(Model model) {
        String correlationId = UUID.randomUUID().toString();
        MDC.put("correlationId", correlationId);
        log.info("PDF generator page accessed - correlationId: {}", correlationId);

        model.addAttribute("pdf", new Pdf());
        return "pdf/generator";
    }

    @PostMapping("/pdf-generator")
    public String generatePdf(@Valid Pdf pdf, BindingResult bindingResult) {
        String correlationId = UUID.randomUUID().toString();
        MDC.put("correlationId", correlationId);

        if (bindingResult.hasErrors()) {
            log.warn("PDF generation validation failed - correlationId: {}", correlationId);
            return "redirect:/pdf-generator";
        } else {
            try {
                byte[] pdfBytes = generateSamplePdf(pdf.getName(), pdf.getContent());

                // Cloud-native: In production, upload to S3
                if (storageEnabled) {
                    log.info("PDF storage enabled, would upload to S3 bucket: {} - correlationId: {}", s3BucketName, correlationId);
                    // TODO: Implement S3 upload using AWS SDK
                    // s3Client.putObject(s3BucketName, pdf.getName() + ".pdf", pdfBytes);
                }

                pdfService.savePdf(pdf);
                log.info("PDF metadata saved successfully - correlationId: {}", correlationId);
            } catch (DocumentException e) {
                log.error("Document generation error - correlationId: {}, error: {}", correlationId, e.getMessage(), e);
                model.addAttribute("error", "Failed to generate PDF document");
                return "pdf/generator";
            } catch (IOException e) {
                log.error("IO error during PDF generation - correlationId: {}, error: {}", correlationId, e.getMessage(), e);
                model.addAttribute("error", "Failed to generate PDF due to IO error");
                return "pdf/generator";
            } finally {
                MDC.remove("correlationId");
            }
            return "pdf/success";
        }
    }

}
