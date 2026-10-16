package lab.udf;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import org.apache.hadoop.hive.ql.exec.Description;
import org.apache.hadoop.hive.ql.exec.UDFArgumentException;
import org.apache.hadoop.hive.ql.exec.UDFArgumentLengthException;
import org.apache.hadoop.hive.ql.metadata.HiveException;
import org.apache.hadoop.hive.ql.udf.generic.GenericUDF;
import org.apache.hadoop.hive.serde2.objectinspector.ObjectInspector;
import org.apache.hadoop.hive.serde2.objectinspector.ObjectInspectorFactory;
import org.apache.hadoop.hive.serde2.objectinspector.PrimitiveObjectInspector;
import org.apache.hadoop.hive.serde2.objectinspector.primitive.PrimitiveObjectInspectorFactory;

/**
 * Hive UDF used as explode(default.format_json_list(str10)).
 * Returns one string per top-level JSON array element so get_json_object can
 * read $.filemd5, $.url, $.domain and $.info.attr.
 * A single JSON object is returned as a one-element list.
 * Text that is neither an array nor an object yields an empty list.
 */
@Description(name = "format_json_list", value = "_FUNC_(json) - JSON array elements as strings")
public class FormatJsonList extends GenericUDF {
  private PrimitiveObjectInspector input;

  @Override
  public ObjectInspector initialize(ObjectInspector[] arguments) throws UDFArgumentException {
    if (arguments.length != 1) {
      throw new UDFArgumentLengthException("format_json_list takes one string argument");
    }
    if (arguments[0].getCategory() != ObjectInspector.Category.PRIMITIVE) {
      throw new UDFArgumentException("format_json_list expects a string");
    }
    input = (PrimitiveObjectInspector) arguments[0];
    return ObjectInspectorFactory.getStandardListObjectInspector(
        PrimitiveObjectInspectorFactory.javaStringObjectInspector);
  }

  @Override
  public Object evaluate(DeferredObject[] arguments) throws HiveException {
    Object raw = arguments[0].get();
    if (raw == null) {
      return Collections.emptyList();
    }
    Object value = input.getPrimitiveJavaObject(raw);
    if (value == null) {
      return Collections.emptyList();
    }
    return split(value.toString());
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

  @Override
  public String getDisplayString(String[] children) {
    return "format_json_list(" + (children.length == 0 ? "" : children[0]) + ")";
  }
}
