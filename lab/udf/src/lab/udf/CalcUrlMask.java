package lab.udf;

import org.apache.hadoop.hive.ql.exec.Description;
import org.apache.hadoop.hive.ql.exec.UDFArgumentException;
import org.apache.hadoop.hive.ql.exec.UDFArgumentLengthException;
import org.apache.hadoop.hive.ql.metadata.HiveException;
import org.apache.hadoop.hive.ql.udf.generic.GenericUDF;
import org.apache.hadoop.hive.serde2.objectinspector.ObjectInspector;
import org.apache.hadoop.hive.serde2.objectinspector.PrimitiveObjectInspector;
import org.apache.hadoop.hive.serde2.objectinspector.primitive.PrimitiveObjectInspectorFactory;

/**
 * One-argument Hive UDF. Documented behavior is to drop the scheme and port
 * and keep the rest of the URL. The Trino two-argument signature is recorded
 * as still needing adaptation; the second argument is not specified here.
 */
@Description(name = "calc_url_mask", value = "_FUNC_(url) - drop scheme and port")
public class CalcUrlMask extends GenericUDF {
  private PrimitiveObjectInspector input;

  @Override
  public ObjectInspector initialize(ObjectInspector[] arguments) throws UDFArgumentException {
    if (arguments.length != 1) {
      throw new UDFArgumentLengthException("calc_url_mask takes one string argument");
    }
    if (arguments[0].getCategory() != ObjectInspector.Category.PRIMITIVE) {
      throw new UDFArgumentException("calc_url_mask expects a string");
    }
    input = (PrimitiveObjectInspector) arguments[0];
    return PrimitiveObjectInspectorFactory.javaStringObjectInspector;
  }

  @Override
  public Object evaluate(DeferredObject[] arguments) throws HiveException {
    Object raw = arguments[0].get();
    if (raw == null) {
      return null;
    }
    Object value = input.getPrimitiveJavaObject(raw);
    if (value == null) {
      return null;
    }
    return mask(value.toString());
  }

  static String mask(String raw) {
    if (raw == null) {
      return null;
    }
    String text = raw.trim();
    int scheme = text.indexOf("://");
    if (scheme > 0) {
      String head = text.substring(0, scheme);
      if (head.matches("[A-Za-z][A-Za-z0-9+.-]*")) {
        text = text.substring(scheme + 3);
      }
    }
    int hostEnd = text.length();
    int slash = text.indexOf('/');
    int query = text.indexOf('?');
    int hash = text.indexOf('#');
    if (slash >= 0) {
      hostEnd = Math.min(hostEnd, slash);
    }
    if (query >= 0) {
      hostEnd = Math.min(hostEnd, query);
    }
    if (hash >= 0) {
      hostEnd = Math.min(hostEnd, hash);
    }
    String host = text.substring(0, hostEnd);
    String rest = text.substring(hostEnd);
    host = stripPort(host);
    return host + rest;
  }

  private static String stripPort(String host) {
    int bracket = host.lastIndexOf(']');
    int colon = host.lastIndexOf(':');
    if (colon < 0) {
      return host;
    }
    if (bracket >= 0 && colon < bracket) {
      return host;
    }
    String port = host.substring(colon + 1);
    if (!port.isEmpty() && port.chars().allMatch(Character::isDigit)) {
      return host.substring(0, colon);
    }
    return host;
  }

  @Override
  public String getDisplayString(String[] children) {
    return "calc_url_mask(" + (children.length == 0 ? "" : children[0]) + ")";
  }
}
