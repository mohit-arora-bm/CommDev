public with sharing class AC_SObjectDescribe {
    //internal implementation details
    private Schema.SObjectType token;
    private Schema.SObjectField nameField;
    private Schema.DescribeSObjectResult describe { //lazy load - keep this leightweight until we need more data
        get{
            if(describe == null)
                describe = token.getDescribe();
            return describe;
        }
        set;
    }
    private Map<String,Schema.SObjectField> fields {
        get{
            if(fields == null)
                fields = describe.fields.getMap();
            return fields;
        }
        set;
    }
    private Map<String,Schema.FieldSet> fieldSets {
        get{
            if(fieldSets == null)
                fieldSets = describe.fieldSets.getMap();
            return fieldSets;
        }
        set;
    }
    private FieldsMap wrappedFields {
        get{
            if(wrappedFields == null){
                wrappedFields = new FieldsMap(this.fields);
            }
            return wrappedFields;
        }
        set;
    }

    private AC_SObjectDescribe(Schema.SObjectType token){    
        if(token == null)
            throw new InvalidDescribeException('Invalid SObject type: null');
        if(instanceCache.containsKey( String.valueOf(token) ))
            throw new DuplicateDescribeException(token + ' is already in the describe cache');
        this.token = token;
        instanceCache.put( String.valueOf(token).toLowerCase() , this);
    }

    //public instace methods
    /**
     * Returns the Schema.SObjectType this AC_SObjectDescribe instance is based on.
    **/
    public Schema.SObjectType getSObjectType(){
        return token;
    }
    /**
     * This method is a convenient shorthand for calling getField(name, true)
    **/
    public Schema.SObjectField getField(String name){
        return this.getField(name, true);
    }
    /**
     * This method provides a simplified shorthand for calling #getFields and getting the provided field.
     * Additionally it handles finding the correct SObjectField for relationship notation,
     * e.g. getting the Account field on Contact would fail without being referenced as AccountId - both work here.
    **/
    public Schema.SObjectField getField(String fieldName, boolean implyNamespace){
        Schema.SObjectField result = wrappedFields.get( 
            (fieldName.endsWithIgnoreCase('__r') ? //resolve custom field cross-object (__r) syntax
            (fieldName.removeEndIgnoreCase('__r')+'__c') :
            fieldName),
            implyNamespace
        ); 
        if(result == null){
            result = wrappedFields.get(fieldName+'Id', implyNamespace); //in case it's a standard lookup in cross-object format
        }
        System.debug(result);
        return result;
    }
    
    /**
    * Returns the field where isNameField() is true (if any); otherwise returns null
    **/
    public Schema.SObjectField getNameField()
    {
        if(nameField == null) {
            for(Schema.SObjectField field : wrappedFields.values()) {
                if(field.getDescribe().isNameField()) {
                    nameField = field;
                    break;
                }
            }
        }
        return nameField;
    }
    
    /**
     * Returns the raw Schema.DescribeSObjectResult an AC_SObjectDescribe instance wraps.
    **/
    public Schema.DescribeSObjectResult getDescribe(){
        System.debug(describe);
        return describe;
    }
    /**
     * This method returns the raw data and provides no namespace handling.
     * Due to this, __use of this method is discouraged__ in favor of getFields(). 
    **/
    public Map<String,Schema.SObjectField> getFieldsMap(){
        return fields;
    }
    public FieldsMap getFields(){
        return wrappedFields;
    }
    public Map<String,Schema.FieldSet> getFieldSetsMap(){
        return fieldSets;
    }



    private static Map<String,Schema.SObjectType> rawGlobalDescribe {
        get{
            if(rawGlobalDescribe == null)
                rawGlobalDescribe = Schema.getGlobalDescribe();
            return rawGlobalDescribe;
        }
        set;
    }
    private static GlobalDescribeMap wrappedGlobalDescribe{
        get{
            if(wrappedGlobalDescribe == null){
                wrappedGlobalDescribe = new GlobalDescribeMap(rawGlobalDescribe);
            }
            return wrappedGlobalDescribe;
        }
        set;
    }
    /**
     * This is used to cache AC_SObjectDescribe instances as they're consutrcted
     * to prevent repeatedly re-constructing the same type.
     * These instances are not guaranteed to be, but typically will be, unique per sObject type due to the presence of flushCache.
    **/
    private static Map<String,AC_SObjectDescribe> instanceCache {get{
            if(instanceCache == null)
                instanceCache = new Map<String,AC_SObjectDescribe>();
            return instanceCache;
        } 
        set;
    }
    public static AC_SObjectDescribe getDescribe(String sObjectName){
        if(String.isBlank(sObjectName))
            return null;
        AC_SObjectDescribe result = instanceCache.get(sObjectName.toLowerCase());
        if(result == null){
            Schema.SObjectType token = wrappedGlobalDescribe.get(sObjectName.toLowerCase());
            if(token == null)
                result = null;
            else
                result = new AC_SObjectDescribe(token);
        }
        return result;
    }
    public static AC_SObjectDescribe getDescribe(Schema.SObjectType token){
        if(token == null)
            return null;
        AC_SObjectDescribe result = instanceCache.get(String.valueOf(token).toLowerCase());
        if(result == null)
            result = new AC_SObjectDescribe(token);      
        return result;
    }
    public static AC_SObjectDescribe getDescribe(Schema.DescribeSObjectResult nativeDescribe){
        if(nativeDescribe == null)
            return null;
        AC_SObjectDescribe result = instanceCache.get(nativeDescribe.getName().toLowerCase());
        if(result == null)
            result = new AC_SObjectDescribe(nativeDescribe.getSobjectType());        
        return result;
    }
    public static AC_SObjectDescribe getDescribe(SObject instance){
        if(instance == null)
            return null;
        return getDescribe(instance.getSobjectType());
    }

    //returns the same results as the native method, just with caching built in to avoid limits
    public static Map<String,SObjectType> getRawGlobalDescribe(){
        return rawGlobalDescribe;
    }
    public static GlobalDescribeMap getGlobalDescribe(){
        return wrappedGlobalDescribe;
    }
    //Useful when working in heap space constrained environments. 
    //Existing references to AC_SObjectDescribe instances will continue to work.
    public static void flushCache(){
        rawGlobalDescribe = null;
        instanceCache = null;
    }


    /**
     * This class handles emulating a Map<String,Object>'s non-mutating instance methods and helps navigate the complex topic of
     * handling implicit namespace behavior like pre-APIv29 did, while also allowing fully qualified references.
     * Note that this requires the API version of AC_SObjectDescribe to be 29 or higher to function properly.
     *
     * Due to the lack of language support for covariant return types sublasses are responsible for implementing the get methods.
     * A minimal implementation of these would be a cast and returning getObject's result.
    **/
    private abstract class NamespacedAttributeMap{
        @testVisible
        protected String currentNamespace;
        protected Map<String,Object> values;

        protected NamespacedAttributeMap(Map<String,Object> values){
            //namespace detection courtesey http://salesforce.stackexchange.com/a/28977/60
            currentNamespace = AC_SObjectDescribe.class.getName().substringBefore('AC_SObjectDescribe').removeEnd('.').toLowerCase();
            this.values = values;
        }
        //A no-args constructor to allow subclasses with different contructor signatures
        protected NamespacedAttributeMap(){
            this(new Map<String,Object>());
        }
        /**
         * A convenient shortcut for invoking #getObject(name, true)
        **/
        protected virtual Object getObject(String name){
            return this.getObject(name, true);
        }
        /**
         *  
        **/
        protected virtual Object getObject(String name, Boolean implyNamespace){
            if(name == null) //short-circuit lookup logic since null can't possibly be a valid field name, and it saves us null checking
                return null;
            String preferredValue = ((implyNamespace ? currentNamespace+'__' : '') + name).toLowerCase();
            if(values.containsKey(preferredValue)){
                return values.get(preferredValue);
            }else if(implyNamespace){
                return values.get(name.toLowerCase());
            }else{
                return null;
            }
        }
        public virtual Boolean containsKey(String name){
            return this.containsKey(name, true);
        }
        public virtual Boolean containsKey(String name, Boolean implyNamespace){
            if(name == null) //short-circuit lookup logic since null can't possibly be a valid field name, and it saves us null checking
                return null;
            String preferredValue = ((implyNamespace ? currentNamespace+'__' : '') + name).toLowerCase();
            return (
                values.containsKey(preferredValue) ||
                implyNamespace && values.containsKey(name.toLowerCase())
            );
        }
        public virtual Integer size(){
            return values.size();
        }
        /**
         * Returns the key set of the map.
         * Note: unlike other NamespacedAttributeMap methods keySet defaults implyNamespace to false if not specified.
        **/
        public virtual Set<String> keySet(){
            return this.keySet(false);
        }
        public virtual Set<String> keySet(Boolean implyNamespace){
            if(implyNamespace){
                Set<String> result = new Set<String>();
                for(String key:values.keySet()){
                    result.add(
                        key.removeStartIgnoreCase(currentNamespace+'__')
                    );
                }
                return result;
            }else{
                return values.keySet();
            }
        }
    }

    /**
     * A subclass of NamespacedAttributeMap for handling the data returned by #Schema.DescribeSObjectResult.fields.getMap
    **/
    public class FieldsMap extends NamespacedAttributeMap{

        @testVisible
        private FieldsMap(Map<String,Schema.SObjectField> values){
            super(values);
        }

        public Schema.SObjectField get(String name){
            return this.get(name, true);
        }
        public Schema.SObjectField get(String name, Boolean implyNamespace){
            return (Schema.SObjectField) this.getObject(name, implyNamespace);
        }
        public List<Schema.SObjectField> values(){
            return (List<Schema.SObjectField>) values.values();
        }

    }
    /**
     * A subclass of NamespacedAttributeMap for handling the data returned by #Schema.getGlobalDescribe
    **/
    public class GlobalDescribeMap extends NamespacedAttributeMap{
        @testVisible
        private GlobalDescribeMap(Map<String,Schema.SObjectType> values){
            super(values);
        }

        public Schema.SObjectType get(String name){
            return this.get(name, true);
        }
        public Schema.SObjectType get(String name, Boolean implyNamespace){
            return (Schema.SObjectType) this.getObject(name, implyNamespace);
        }
        public List<Schema.SObjectType> values(){
            return (List<Schema.SObjectType>) values.values();
        }
    }


    public abstract class DescribeException extends Exception{}
    public class DuplicateDescribeException extends DescribeException{} //Test coverage for this requires APIv28's @testVisbile annotation to force exception cases.
    public class InvalidDescribeException extends DescribeException{}
}