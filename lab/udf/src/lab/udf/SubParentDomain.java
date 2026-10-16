package lab.udf;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import org.apache.hadoop.hive.ql.exec.Description;
import org.apache.hadoop.hive.ql.exec.UDFArgumentException;
import org.apache.hadoop.hive.ql.exec.UDFArgumentLengthException;
import org.apache.hadoop.hive.ql.metadata.HiveException;
import org.apache.hadoop.hive.ql.udf.generic.GenericUDTF;
import org.apache.hadoop.hive.serde2.objectinspector.ObjectInspector;
import org.apache.hadoop.hive.serde2.objectinspector.ObjectInspectorFactory;
import org.apache.hadoop.hive.serde2.objectinspector.PrimitiveObjectInspector;
import org.apache.hadoop.hive.serde2.objectinspector.StructObjectInspector;
import org.apache.hadoop.hive.serde2.objectinspector.primitive.PrimitiveObjectInspectorFactory;

/**
 * UDTF. evil.example.com yields evil.example.com, example.com, com.
 * One trailing dot is removed so the last label is not empty.
 */
@Description(name = "sub_parent_domain", value = "_FUNC_(domain) - one row per domain suffix")
public class SubParentDomain extends GenericUDTF {
  private PrimitiveObjectInspector input;

  @Override
  public StructObjectInspector initialize(ObjectInspector[] arguments) throws UDFArgumentException {
    if (arguments.length != 1) {
      throw new UDFArgumentLengthException("sub_parent_domain takes one string argument");
    }
    if (arguments[0].getCategory() != ObjectInspector.Category.PRIMITIVE) {
      throw new UDFArgumentException("sub_parent_domain expects a string");
    }
    input = (PrimitiveObjectInspector) arguments[0];
    return ObjectInspectorFactory.getStandardStructObjectInspector(
        Collections.singletonList("sub_domain"),
        Collections.singletonList(PrimitiveObjectInspectorFactory.javaStringObjectInspector));
  }

  @Override
  public void process(Object[] record) throws HiveException {
    if (record == null || record.length == 0 || record[0] == null) {
      return;
    }
    Object value = input.getPrimitiveJavaObject(record[0]);
    if (value == null) {
      return;
    }
    for (String suffix : suffixes(value.toString())) {
      forward(new Object[] {suffix});
    }
  }

  static List<String> suffixes(String raw) {
    if (raw == null) {
      return Collections.emptyList();
    }
    String text = raw.trim();
    if (text.endsWith(".")) {
      text = text.substring(0, text.length() - 1);
    }
    if (text.isEmpty()) {
      return Collections.emptyList();
    }
    String[] labels = text.split("\\.", -1);
    List<String> rows = new ArrayList<>();
    for (int start = 0; start < labels.length; start++) {
      StringBuilder suffix = new StringBuilder();
      for (int index = start; index < labels.length; index++) {
        if (index > start) {
          suffix.append('.');
        }
        suffix.append(labels[index]);
      }
      rows.add(suffix.toString());
    }
    return rows;
  }

  @Override
  public void close() {}
}
