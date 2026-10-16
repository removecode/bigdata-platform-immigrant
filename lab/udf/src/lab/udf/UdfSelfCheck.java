package lab.udf;

import java.util.Arrays;
import java.util.List;

/** Checks the three UDF bodies against the examples recorded in the docs. */
public final class UdfSelfCheck {
  public static void main(String[] args) {
    List<String> elements = FormatJsonList.split(
        "[{\"filemd5\":\"abc\",\"info\":{\"attr\":\"0\"}},{\"url\":\"http://a\"}]");
    expect(elements.size() == 2, "json array size");
    expect(elements.get(0).contains("\"filemd5\":\"abc\""), "filemd5 element");
    expect(elements.get(0).contains("\"attr\":\"0\""), "nested attr");
    expect(elements.get(1).contains("\"url\":\"http://a\""), "url element");
    expect(FormatJsonList.split("{\"domain\":\"evil.example.com\"}").size() == 1, "single object");
    expect(FormatJsonList.split("not-json").isEmpty(), "non json");

    expect("evil.example.com/a/b?x=1".equals(CalcUrlMask.mask("http://evil.example.com:8080/a/b?x=1")),
        "scheme and port");
    expect("host/path".equals(CalcUrlMask.mask("https://host/path")), "https");
    expect("host/x".equals(CalcUrlMask.mask("host:443/x")), "port without scheme");
    expect(CalcUrlMask.mask(null) == null, "null url");

    List<String> suffixes = SubParentDomain.suffixes("evil.example.com");
    expect(suffixes.equals(Arrays.asList("evil.example.com", "example.com", "com")),
        "domain suffixes " + suffixes);
    System.out.println("udf self-check ok");
  }

  private static void expect(boolean condition, String label) {
    if (!condition) {
      throw new IllegalStateException(label);
    }
  }

  private UdfSelfCheck() {}
}
