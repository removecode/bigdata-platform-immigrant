package lab.udfsr;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * StarRocks Java UDF twin of lab.udf.FormatJsonList (Hive), used as
 * unnest(default.format_json_list(str10)). The splitting code is copied from
 * the Hive class unchanged so both engines return the same elements: one string
 * per top-level JSON array element, a single JSON object as a one-element list,
 * anything else as an empty list.
 */
public class FormatJsonList {
  public List<String> evaluate(String raw) {
    return split(raw);
  }

  static List<String> split(String raw) {
    if (raw == null) {
      return Collections.emptyList();
    }
    String text = raw.trim();
    if (text.isEmpty()) {
      return Collections.emptyList();
    }
    List<String> items = new ArrayList<>();
    if (text.charAt(0) == '[') {
      collectArray(text, items);
      return items;
    }
    if (text.charAt(0) == '{') {
      items.add(text);
      return items;
    }
    return items;
  }

  private static void collectArray(String text, List<String> items) {
    int index = 1;
    while (index < text.length()) {
      char current = text.charAt(index);
      if (current == ']') {
        return;
      }
      if (Character.isWhitespace(current) || current == ',') {
        index++;
        continue;
      }
      int end = skipValue(text, index);
      String element = text.substring(index, end).trim();
      if (!element.isEmpty()) {
        items.add(element);
      }
      index = end;
    }
  }

  private static int skipValue(String text, int start) {
    char current = text.charAt(start);
    if (current == '"') {
      return skipString(text, start);
    }
    if (current == '{' || current == '[') {
      int depth = 0;
      boolean inString = false;
      boolean escaped = false;
      for (int index = start; index < text.length(); index++) {
        char ch = text.charAt(index);
        if (inString) {
          if (escaped) {
            escaped = false;
          } else if (ch == '\\') {
            escaped = true;
          } else if (ch == '"') {
            inString = false;
          }
          continue;
        }
        if (ch == '"') {
          inString = true;
          continue;
        }
        if (ch == '{' || ch == '[') {
          depth++;
        } else if (ch == '}' || ch == ']') {
          depth--;
          if (depth == 0) {
            return index + 1;
          }
        }
      }
      return text.length();
    }
    int index = start;
    while (index < text.length()) {
      char ch = text.charAt(index);
      if (ch == ',' || ch == ']' || ch == '}') {
        break;
      }
      index++;
    }
    return index;
  }

  private static int skipString(String text, int start) {
    boolean escaped = false;
    for (int index = start + 1; index < text.length(); index++) {
      char ch = text.charAt(index);
      if (escaped) {
        escaped = false;
        continue;
      }
      if (ch == '\\') {
        escaped = true;
        continue;
      }
      if (ch == '"') {
        return index + 1;
      }
    }
    return text.length();
  }
}
